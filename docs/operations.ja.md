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
| browserhive / capture-ledger | `browserhive` | `http://seaweedfs.crawler-storage:8333` |
| wacz-validator | `wacz-validator` | `http://seaweedfs.crawler-storage:8333` |

**鍵は bucket 名と同じ**（`accessKey` も `secretKey` も）。identity は bucket ごとに分かれて
いて、自分の bucket の外は触れない。使い捨ての store（消費者の `--own-store`）を見るときは、
宛先だけ `http://seaweedfs.<project>:8333` に読み替える —— `<project>` は消費者の compose の
project 名で、そのまま DNS ドメインになる。

```sh
export AWS_ACCESS_KEY_ID=browserhive
export AWS_SECRET_ACCESS_KEY=browserhive
export AWS_ENDPOINT_URL_S3=http://seaweedfs.crawler-storage:8333
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

共有 store は `127.0.0.1` にも publish している（`8333`・`8888`・`9333`）ので、
`http://127.0.0.1:8333` でも同じ所に届く。**使い捨ての store は publish しない** ——
プラットフォームの DNS 名は host からも引けるので、出す必要が無く、port も衝突しない。

## 全ファイルを削除する

bucket は残したまま、中身だけ空にする。**開発中にいちばん使う操作。**

```sh
sh scripts/wipe.sh browserhive                                    # 共有 store
sh scripts/wipe.sh browserhive http://seaweedfs.browserhive:8333  # 使い捨ての store
```

消えるのは成果物だけで、bucket も SeaweedFS の状態も残る。次の取り込みは何も作り直さずに
そのまま書ける。消す前に何が消えるか見たいときは `--dryrun` を足す（`aws` にそのまま渡る）。

```sh
sh scripts/wipe.sh browserhive "" --dryrun
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
http://seaweedfs.crawler-storage:8888/buckets/browserhive/
```

## weed shell —— SeaweedFS 自身の CLI

S3 API では見えないもの（filer のメタデータ、実際のディスク使用量）は `weed shell` から見る。
対話シェルだが、標準入力に流し込めば 1 行でも使える。共有 store のコンテナの名前は
`seaweedfs.crawler-storage`。

```sh
printf 'fs.du /buckets/browserhive\n' | container exec -i seaweedfs.crawler-storage weed shell
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
sh scripts/stack.sh down
container rm seaweedfs.crawler-storage
container volume rm crawler-storage_seaweedfs-data   # 正確な名前は container volume ls
sh scripts/stack.sh up
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
| `aws` が接続を拒まれる | store が起動しているか（`container ls` に `seaweedfs.crawler-storage`）。`sh scripts/stack.sh up` |
| `403` が返る | 鍵が bucket 名と揃っているか。identity は bucket ごとに分かれていて、他人の bucket は触れない |
| `NoSuchBucket` | entrypoint の bucket 作成が終わっていない。`aws s3 ls` で待つ |
| 見覚えのない bucket が並ぶ | 宛先が効いていない —— 本物の AWS を見ている。`AWS_PROFILE` も疑う |
| 消したのに容量が減らない | `s3.bucket.list` ではなく `fs.du` を見る |
| 匿名で読めるはずのものが 403 | その bucket が `S3_ANONYMOUS_READ_BUCKETS` に入っているか（一覧は匿名では常に 403） |
