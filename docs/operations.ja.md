# SeaweedFS の操作

この repo の設定で立てた store を、開発中に手で触るためのページ。英語版は
[operations.md](operations.md)。store そのものの立て方と設定は [README](../README.md) に、
成果物ストアの設計（外部 S3 への向け方、アドレッシング方式、region の意味）は消費者側の
docs にある。

いちばんよく使うのは、取り込みを試すたびに溜まる成果物を消すこと。**この 1 行で足りる。**

```sh
sh scripts/wipe.sh <bucket>
```

以下はその周辺。

## 自分の store を指す

このページのコマンドは `<bucket>` と宛先を自分で決める。消費者ごとの値:

| 消費者 | bucket と鍵 | 宛先 |
|---|---|---|
| browserhive | `browserhive` | `http://seaweedfs.browserhive:8333` |
| capture-ledger | `browserhive`（browserhive が置いたものを読む） | `http://seaweedfs.capture-ledger:8333` |
| wacz-validator | `wacz-validator` | `http://seaweedfs.wacz-validator:8333` |

**鍵は bucket 名と同じ**（`accessKey` も `secretKey` も）。宛先の `seaweedfs.<project>` の
`<project>` は compose の project 名で、そのまま DNS ドメインになる —— store は消費者ごとに
1 つずつ立っているので、repo が変われば宛先も変わる。

```sh
export AWS_ACCESS_KEY_ID=browserhive
export AWS_SECRET_ACCESS_KEY=browserhive
export AWS_ENDPOINT_URL_S3=http://seaweedfs.browserhive:8333
export AWS_REGION=us-east-1
```

> [!CAUTION]
> **宛先を必ず立てる。** `--endpoint-url`（か `AWS_ENDPOINT_URL_S3`）を書き忘れると、`aws` は
> **本物の AWS を見に行く**。手元に `~/.aws/config` があれば、そのプロファイルの資格情報で。
> `s3 rm --recursive` のような取り返しのつかないコマンドを日常的に打つなら、毎回フラグを
> 書くより環境変数で固定するほうが安全。

> [!CAUTION]
> **`AWS_PROFILE` が設定されていると、上の環境変数より静かに勝つ。** 意図した鍵で
> 話していないのに、エラーは「資格情報が違う」としか言わない。`unset AWS_PROFILE` するか、
> `scripts/wipe.sh` を使う（中で外している）。

region は指定しなくてよい。SeaweedFS は値を無視するが、SigV4 の署名には必ず載る ——
`~/.aws/config` に何も無い環境では `AWS_REGION=us-east-1` を足す。

コマンドは [AWS CLI](https://docs.aws.amazon.com/cli/) を使う（`brew install awscli`）。
S3 API を話す相手なら何でもよいので、`s5cmd` や `mc` でも同じことはできる。

## 2 つの入り口

この store は 1 プロセスで master / volume / filer / S3 を兼ねている。外から触れる口は 2 つ。

| 口 | 宛先 | 用途 |
|---|---|---|
| S3 API | `:8333` | `aws` CLI。**普段はこちら** |
| Filer | `:8888` | ブラウザで中身を見る |

publish するかは消費者による（capture-ledger と wacz-validator は `127.0.0.1` にも出していて、
browserhive は出していない）。**publish は必須ではない** —— プラットフォームの DNS 名は
host からも引けるので、名前 1 つで足りる。

## 全ファイルを削除する

bucket は残したまま、中身だけ空にする。**開発中にいちばん使う操作。**

```sh
sh scripts/wipe.sh browserhive http://seaweedfs.browserhive:8333
sh scripts/wipe.sh wacz-validator http://seaweedfs.wacz-validator:8333
```

消えるのは成果物だけで、bucket も SeaweedFS の状態も残る。次の取り込みは何も作り直さずに
そのまま書ける。消す前に何が消えるか見たいときは `--dryrun` を足す（`aws` にそのまま渡る）。

```sh
sh scripts/wipe.sh browserhive http://seaweedfs.browserhive:8333 --dryrun
```

素で書くならこう。

```sh
aws s3 rm s3://browserhive/ --recursive
```

> [!NOTE]
> 730 オブジェクト（e2e を数周した後の状態）で **0.7 秒**ほど。件数が増えても `aws` は
> まとめて消すので、体感で待つことはない。

### 消えたことを確かめる

```sh
aws s3 ls s3://browserhive/ --recursive | wc -l   # 0 になる
aws s3 ls                                          # bucket は残っている
```

## 中身を見る

```sh
# 一覧（上位のみ）
aws s3 ls s3://browserhive/

# 全部と件数
aws s3 ls s3://browserhive/ --recursive | wc -l

# 1 つ取り出して中身を見る（browserhive の .result.json はマニフェスト）
aws s3 cp s3://browserhive/<key>.result.json - | jq .

# 手元に落とす
aws s3 cp s3://browserhive/<key>.wacz ./out.wacz
```

ブラウザで眺めるなら Filer が早い。

```
http://seaweedfs.browserhive:8888/buckets/browserhive/
```

## weed shell —— SeaweedFS 自身の CLI

S3 API では見えないもの（filer のメタデータ、実際のディスク使用量）は `weed shell` から見る。
対話シェルだが、標準入力に流し込めば 1 行でも使える。コンテナの名前は `seaweedfs.<project>`
（例: `seaweedfs.browserhive`）。

```sh
printf 'fs.du /buckets/browserhive\n' | container exec -i seaweedfs.browserhive weed shell
```

よく使うもの:

| コマンド | 何が分かるか |
|---|---|
| `fs.ls /buckets` | bucket の一覧 |
| `fs.du /buckets/<bucket>` | 実際に使っている論理サイズ |
| `s3.bucket.list` | bucket と、その size / chunk |
| `fs.rm -r <path>` | 再帰削除（S3 API を通さない） |

> [!CAUTION]
> **`s3.bucket.list` の size は当てにならない。** 全オブジェクトを消した直後でも
> `size:1318264` のような値を返すことがある（同じ時点で `fs.du` は `logical size: 5`）。
> この数字は消したぶんをすぐには引かない。**実際の使用量を見たいなら `fs.du`。**

## store の状態ごとリセットする

成果物ではなく SeaweedFS 自体が怪しいとき（メタデータの破損、資格情報の不一致、bucket が
作られないまま）に使う。**日常の掃除には使わない** —— 上の `wipe.sh` で足りる。

```sh
pnpm run stack:down                                  # 消費者の repo で
container rm seaweedfs.<project>
container volume rm <project>_seaweedfs-data         # 正確な名前は container volume ls
pnpm run stack:up
```

`down` はコンテナを止めるだけで消さない。止まったコンテナが掴んでいる volume は消せない
（`volume … is currently in use`）ので、先に `container rm` する。

volume を落とすと bucket も SeaweedFS のメタデータも消える。次の `up` が volume を、
entrypoint が bucket を作り直す（`etc/init-bucket.sh` が master の応答を待つリトライループを
持っているので、順序を気にする必要はない）。

**成果物を消すと、それを指している台帳の行は残る。** capture-ledger の picker から開くと
replay が 404 を返す。store を作り直すときは、消費者側の DB も作り直すこと。

## 困ったとき

| 症状 | 見るところ |
|---|---|
| `aws` が接続を拒まれる | store が起動しているか（`container ls` に `seaweedfs.<project>`） |
| `403` が返る | 鍵が bucket 名と揃っているか（`S3_ACCESS_KEY_ID` と `S3_BUCKET`） |
| `NoSuchBucket` | entrypoint の bucket 作成が終わっていない。`aws s3 ls` で待つ |
| 見覚えのない bucket が並ぶ | 宛先が効いていない —— 本物の AWS を見ている。`AWS_PROFILE` も疑う |
| 消したのに容量が減らない | `s3.bucket.list` ではなく `fs.du` を見る |
| 匿名で読めるはずのものが 403 | その store が `S3_ANONYMOUS_READ=true` で立っているか（一覧は匿名では常に 403） |
