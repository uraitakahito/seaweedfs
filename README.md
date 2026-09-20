# seaweedfs

crawler の各 repo が共有する SeaweedFS。**store は 1 つだけ立て、3 つの repo がそれを見る。**
設定は submodule として配り、起動もここから行う。

公式 image (`docker.io/chrislusf/seaweedfs`) をそのまま使い、entrypoint と bucket の
初期化だけをここが持つ。image は焼かない。

## なぜ切り出したか

同じ 2 ファイルが browserhive と wacz-validator（当時の waxlens）に別々に置かれ、
**3 ファイルすべてが分岐していた**。しかも capture-ledger（当時の waggle）は自分の写しを
持たず、`browserhive/etc/seaweedfs` を submodule 越しに mount していた —— object store が
欲しいだけなのに browserhive 全体に依存する形になっていた。

分岐の中身は「テンプレートに書かれた identity」「再試行の回数」「env の prefix」の 3 つ
で、**どれも env で表せる**。だから設定ファイルを置かず、entrypoint が identity JSON を
その場で組み立てる。fork する理由が無ければ、fork は起きない。

## 使い方

マシンごとに 1 度だけ（project 名と同じ DNS ドメインを作る）:

```sh
sudo container system dns create crawler-storage
```

立てる。submodule の中からでも同じ store が立つ（project 名も volume も同じ）ので、
消費者の repo から出なくてよい:

```sh
sh scripts/stack.sh up      # または  sh .upstream/seaweedfs/scripts/stack.sh up
sh scripts/stack.sh down
```

宛先は 1 つ。**コンテナからも host からも同じ綴りで引ける。**

```
http://seaweedfs.crawler-storage:8333          S3 API（127.0.0.1:8333 でも届く）
http://seaweedfs.crawler-storage:8888/buckets/ filer の画面
```

### 使い捨ての store を立てたいとき

e2e のように「他と混ざらない store」が要る場面では、消費者が自分の project の中に
`profiles: ["storage"]` として立てる。`container-compose` は `include:` も `extends:` も
使えない（実測: どちらもデコードに失敗する）ので、service ブロックは**写す**。写しの
image の版がずれたら落ちるように、消費者は自分の check で `scripts/check-pin.sh` を走らせる。

```yaml
  seaweedfs:
    profiles: ["storage"]                    # 既定では起きない（日常は共有 store）
    image: docker.io/chrislusf/seaweedfs:4.46
    entrypoint: ["/etc/seaweedfs/entrypoint.sh"]
    environment:
      - S3_BUCKETS=myapp
      - S3_ANONYMOUS_READ_BUCKETS=myapp      # 匿名 Read が要るときだけ
    volumes:
      - ./seaweedfs/etc:/etc/seaweedfs:ro    # submodule の置き場所に合わせる
      - seaweedfs-data:/data
```

## 設定

| env | 必須 | 既定 | 効果 |
|---|---|---|---|
| `S3_BUCKETS` | ✓ | — | 作る bucket をカンマ区切りで。**identity 名も鍵も同じ綴り** |
| `S3_ANONYMOUS_READ_BUCKETS` | | （無し） | 匿名に `Read:<bucket>` を与える bucket をカンマ区切りで |
| `S3_INIT_ATTEMPTS` | | `30` | bucket 作成のリトライ回数（bucket ごと） |

**鍵は bucket 名と同じ。** 1 つの store を複数の消費者が使うので、identity は bucket ごとに
分かれ、`actions` は bucket で絞ってある（`Read:<bucket>` の形）。絞らないと、ある消費者の
鍵で別の消費者の bucket まで触れる —— `scripts/verify.sh` がその 4 つを実物で確かめる
（他人の bucket は一覧が `AccessDenied`、取得と書き込みが不可、自分の bucket には書ける）。

`S3_ANONYMOUS_READ_BUCKETS` は、資格情報を持てない読み手のためにある。browserhive の replay
サービス (nginx 1 枚で S3 の署名をしない) がブラウザに `/wacz/<key>` を素通しさせる
のに使う。**この穴は広げても何も言わない**ので、与えるのは `Read` だけ。輪郭は
`scripts/verify.sh` が実物で確かめる:

```
匿名を与えた bucket    GET 200 / Range GET 206 / 一覧 403 / PUT 403 / DELETE 403 / 別 bucket 403
与えていない bucket    GET 403
```

bucket 名に `"` と `\` は使えない。
identity JSON を `printf` で組み立てているため (image に `jq` も `envsubst` も無い)。
そのまま通すと「資格情報が違う」形の静かな失敗になるので、起動時に FATAL で落とす。

## 運用（消す・見る）

開発中にいちばん使うのは、溜まった成果物を消すこと。**bucket は残したまま中身だけ空にする。**

```sh
sh scripts/wipe.sh <bucket> [endpoint] [aws の追加引数...]
sh scripts/wipe.sh browserhive http://seaweedfs.browserhive:8333 --dryrun
```

全削除・中身の確認・`weed shell`・store ごとのリセット・困ったときの一覧は、
**消費者の repo ではなくここに 1 つだけ**置いてある:

- [docs/operations.ja.md](docs/operations.ja.md)（日本語）
- [docs/operations.md](docs/operations.md)（English）

以前は browserhive の docs にだけ在り、capture-ledger には手順が無く、wacz-validator には
「volume も消す」の 1 行しか無かった。store は 3 つの repo が同じ設定で立てているので、
**触り方も 1 か所に置く。**

## 版を上げる

版の正は `docker-compose.yml` の image の 1 行だけ。README の見本は CI が
`scripts/check-pin.sh README.md` で揃える。

1. `docker-compose.yml` と README の見本の版を書き換える
2. `scripts/verify.sh` を回す。消費者が頼っている挙動を、`etc/` の entrypoint をそのまま
   使う使い捨てのコンテナで 1 つずつ確かめる —— 資格情報での読み書き、匿名 Read の輪郭、
   誤った秘密鍵、署名付き URL、鍵の長さの上限（255 バイト）、空にして再起動した後の
   書き込み。終了コードは赤の数
3. タグを打ち、各消費者で submodule と自分の compose の版を上げる（check-pin.sh が
   片方だけの更新を落とす）。dev の store は作り直す

**4.27 未満に戻さないこと。** 4.26 以前は、最後の記録が削除のボリュームを起動時の検査が
壊れていると誤判定し、読み取り専用で読み込む（上流 [#9563](https://github.com/seaweedfs/seaweedfs/issues/9563)、
4.27 で修正）。バケット用のボリュームが 1 本しか無いスタックでは、バケットを空にして
再起動しただけで書き込みが止まる。`scripts/verify.sh 4.23` はその 1 行だけが赤になる。

`verify.sh` が要るのは `container`（Apple Container）、`aws`（AWS CLI v2）、`curl`。S3 は
`127.0.0.1:18333`（`VERIFY_PORT` で変えられる）に publish するので、他のスタックが
動いていても回せる。

## 消費者

| repo | 置き場所 | bucket | 検査 | 特記 |
|---|---|---|---|---|
| browserhive | `seaweedfs/` | `browserhive` | `lint:seaweedfs-pin`・`lint:store-name` | e2e だけ `--own-store` で使い捨ての store を立てる |
| capture-ledger | `.upstream/seaweedfs/` | `browserhive` | `check:seaweedfs-pin`・`check:store-name` | browserhive が置いたものを読む。署名付き URL を発行する |
| wacz-validator | `seaweedfs/` | `wacz-validator` | `check:seaweedfs-pin`・`check:store-name` | 匿名 Read は使わない。店が要る試験は無い（人が触るだけ） |

共有 store の bucket は `docker-compose.yml` の `S3_BUCKETS` に並べる。消費者が増えたら、
そこに 1 語足す。`scripts/check-store-name.sh` は、消費者の repo に `seaweedfs.<自分の
project 名>` が残っていないかを見る（自前の store を指すのが正しい場所だけ、引数で除外する）。
