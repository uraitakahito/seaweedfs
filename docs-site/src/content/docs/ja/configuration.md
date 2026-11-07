---
title: 設定
description: 3 つの env と、bucket ごとに分かれた identity の作られ方。
---

設定は `docker-compose.yml` の env だけ。設定ファイルは置かず、`etc/entrypoint.sh` が
identity の JSON をその場で組み立てる —— fork する理由が無ければ、fork は起きない。
枠（下の節）だけは env にせず、entrypoint に固定してある。

| env | 必須 | 既定 | 効果 |
|---|---|---|---|
| `S3_BUCKETS` | ✓ | — | 作る bucket をカンマ区切りで。**identity 名も鍵も同じ綴り** |
| `S3_ANONYMOUS_READ_BUCKETS` | | （無し） | 匿名に `Read:<bucket>` を与える bucket をカンマ区切りで |
| `S3_INIT_ATTEMPTS` | | `30` | bucket 作成のリトライ回数（bucket ごと） |

## 枠

`etc/entrypoint.sh` が次の 2 つを固定している。消費者ごとに変える理由が無いので env にしていない。

| 設定 | 値 | SeaweedFS の既定 | 効果 |
|---|---|---|---|
| `-volume.max` | `64` | `8` | volume の本数の上限。1 本は 1 GiB（`-master.volumeSizeLimitMB=1024`） |
| `WEED_MASTER_VOLUME_GROWTH_COPY_1` | `1` | `7` | 1 度に増やす本数 |

既定のままだと、起動直後に既定の collection が 7 本を取り、bucket に 1 本しか残らない。それが埋まると
書き込みが `500 InternalError` で止まる。

- **広げ方:** `sh scripts/stack.sh up` でコンテナを作り直す。named volume の中身は残る
- **戻り方:** 古い版の entrypoint から `up` すると、黙って枠 8 に戻る。消費者は submodule を上げてから打つ
- **見方:** `curl -s http://127.0.0.1:9333/dir/status` の `Topology.Max`・`Free`・`Layouts[].writables`
- **確かめ:** `scripts/verify.sh` が、枠の本数と、初めて PUT したときに増える本数を見る

## 鍵は bucket 名と同じ

1 つの store を複数の消費者が使うので、identity は bucket ごとに分かれ、`actions` は bucket で
絞ってある（`Read:<bucket>` の形）。絞らないと、ある消費者の鍵で別の消費者の bucket まで
触れる。`scripts/verify.sh` がその 4 つを実物で確かめる —— 他人の bucket は一覧が
`AccessDenied`、取得と書き込みが不可、自分の bucket には書ける。

## 匿名 Read の輪郭

`S3_ANONYMOUS_READ_BUCKETS` は、資格情報を持てない読み手のためにある。
[replayweb-server](https://github.com/uraitakahito/replayweb-server)（Node の小さな server で、S3 の署名をしない）がブラウザに `/wacz/<key>` を素通しさせるのに使う。
**この穴は広げても何も言わない**ので、与えるのは `Read` だけ。輪郭は `scripts/verify.sh` が
実物で確かめる:

```
匿名を与えた bucket    GET 200 / Range GET 206 / 一覧 403 / PUT 403 / DELETE 403 / 別 bucket 403
与えていない bucket    GET 403
```

## bucket 名の制限

bucket 名に `"` と `\` は使えない。identity JSON を `printf` で組み立てているため（image に
`jq` も `envsubst` も無い）。そのまま通すと「資格情報が違う」形の静かな失敗になるので、
起動時に FATAL で落とす。
