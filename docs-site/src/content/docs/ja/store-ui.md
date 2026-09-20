---
title: 成果物を探す
description: 取り込んだものを新しい順に並べて見る画面。filer に 1 枚だけ置いてある。
---

取り込んだ成果物を**新しい順**に並べて見るための画面。英語版は [English version](/seaweedfs/store-ui/)。
store の立て方は [クイックスタート](/ja/quickstart/)、消す・数える・`weed shell` は
[運用](/ja/operations/)にある。

```
http://127.0.0.1:8888/ui/index.html
```

`sh scripts/stack.sh up` が毎回置き直すので、用意することは何も無い。

## なぜ画面が要るのか

**S3 の一覧は名前順にしか返らない。** `ListObjectsV2` には並べ替えの引数が無く、鍵を
辞書順で返すとだけ決まっている。filer の素の画面も `weed admin` も同じで、どちらも
日時では並べられない（`weed admin` の並べ替えの引数は効かない。公式 wiki の
「名前・サイズ・更新日時で並べ替えられる」という記述は実装と食い違っている）。

並べ替えは**サーバ側では手に入らない**ので、受け取った側で並べるしかない。この画面は
filer の JSON をそのまま読んで、時刻で並べ直しているだけ。**別のコンテナも、別の
プロセスも増えない。**

## 何が出るか

| 列 | 中身 |
|---|---|
| 時刻 | いちばん新しい成果物の `Mtime`（手元の時間帯）。ここで並べ替える |
| ラベル | 鍵に入っているラベルと correlationId |
| 成果物 | `wacz` / `png` / `html` / `result.json` … 押すと開く |
| 大きさ | その取り込みが書いた合計 |
| taskId | 先頭 8 文字（マウスを載せると全部） |

**1 行が 1 回の取り込み。** 1 回の取り込みは複数のオブジェクトを書くので、鍵の
`{taskId}_{correlationId}[_{label}]*.{拡張子}` という形を見て taskId でまとめている。
この形でない鍵は、まとめずに 1 行ずつ並ぶ（**表示だけの約束で、正しさは何も乗っていない**）。

`.wacz` には ▶ replay が付く。飛び先は自前の [ReplayWeb.page](https://replayweb.page/)
（[BrowserHive](https://github.com/uraitakahito/browserhive) の `replay` プロファイル）で、
**上流に `browserhive` の bucket 1 つだけ**を持つので、この bucket のときにだけ出る。

## 既定で e2e を隠している

e2e を走らせると成果物が数百たまり、自分で撮ったものが埋もれる。実測では
**274 回の取り込みのうち 266 回が e2e** で、隠すと残りは 8 行だった。

「e2e を隠す」を押せば出る。**この画面は隠すだけで、実体は 1 つも減らさない。**
減らすのは [運用](/ja/operations/)の `scripts/wipe.sh` の仕事。

絞り込み（`/` で移動）は鍵・ラベル・taskId のどれにでも当たる。種類で絞る、時刻と
大きさで並べ替える、も上の行から。

## アドレスに付けられるもの

| 引数 | 既定 | 何を変えるか |
|---|---|---|
| `?bucket=` | 最初の bucket | 開いたときに選ばれている bucket |
| `?filer=` | 同じオリジン | filer の宛先（`file://` で開くときに要る） |
| `?replay=` | `https://replay.browserhive` | ▶ replay の飛び先。空文字にすると出さない |
| `?replayBucket=` | `browserhive` | ▶ replay を出す bucket |

`ui/index.html` を手元で直接開いても動く。filer が `Access-Control-Allow-Origin: *` を
返すので、`file://` からでも読める（実測）。

## 置き場所

置くのは `scripts/ui.sh`、置き先は filer の `/ui/index.html` で、**S3 の bucket の外**。

- bucket に置くと、探しやすくするための画面が成果物の一覧に出てしまう
- bucket に置くと `scripts/wipe.sh` で一緒に消える
- filer が配るので画面と JSON が同一オリジンになり、ブラウザの制限を何も踏まない

> [!CAUTION]
> **この画面を公開しない。** 認証は無く、filer の口は `docker-compose.yml` で
> `127.0.0.1` にだけ publish してある前提に乗っている。
>
> 同じ理由で、**ドキュメントのサイト側には置けない**。filer は preflight に
> `Access-Control-Allow-Private-Network` を返さないので、https のページから
> `127.0.0.1` を叩くと Chrome の Private Network Access が止める（実測）。

## 直す

`ui/index.html` は依存の無い 1 ファイルで、ビルドも要らない。直したら置き直すだけ。

```sh
sh scripts/stack.sh up     # up のたびに上書きされる
sh scripts/ui.sh           # 画面だけ置き直す
```

## 困ったとき

| 症状 | 見るところ |
|---|---|
| 「filer から読めませんでした」 | store が起きているか（`sh scripts/stack.sh up`）。`file://` で開いたなら `?filer=http://…:8888` |
| 0 件しか出ない | 「e2e を隠す」が効いている。押して戻す |
| ▶ replay が 502 | replay が起きていない（BrowserHive 側の `replay` プロファイル） |
| ▶ replay が出ない | `browserhive` 以外の bucket を見ている |
| 画面が古い | `sh scripts/stack.sh up` で置き直す |
