# seaweedfs

crawler の各 repo が共有する SeaweedFS の起動設定。**submodule として使う**。

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

単体で立てる:

```sh
container-compose up -d
container-compose down
```

submodule として使う場合は、`docker-compose.yml` の service ブロックを**写す**。
`container-compose` は `include:` も `extends:` も使えないので、共有する手段が無い
(実測: どちらもデコードに失敗する)。写しの image の版がずれたら落ちるように、消費者は
自分の check で `scripts/check-pin.sh` を走らせる（下の「消費者」）。

```yaml
  seaweedfs:
    image: docker.io/chrislusf/seaweedfs:4.46
    entrypoint: ["/etc/seaweedfs/entrypoint.sh"]
    environment:
      - S3_ACCESS_KEY_ID=myapp
      - S3_SECRET_ACCESS_KEY=myapp
      - S3_BUCKET=myapp
    volumes:
      - ./seaweedfs/etc:/etc/seaweedfs:ro   # submodule の置き場所に合わせる
      - seaweedfs-data:/data
```

## 設定

| env | 必須 | 既定 | 効果 |
|---|---|---|---|
| `S3_ACCESS_KEY_ID` | ✓ | — | identity の accessKey |
| `S3_SECRET_ACCESS_KEY` | ✓ | — | secretKey |
| `S3_BUCKET` | ✓ | — | 作る bucket。identity 名も兼ねる |
| `S3_ANONYMOUS_READ` | | `false` | `true` で `anonymous` に `Read:$S3_BUCKET` を与える |
| `S3_INIT_ATTEMPTS` | | `30` | bucket 作成のリトライ回数 |

`S3_ANONYMOUS_READ` は、資格情報を持てない読み手のためにある。browserhive の replay
サービス (nginx 1 枚で S3 の署名をしない) がブラウザに `/wacz/<key>` を素通しさせる
のに使う。**この穴は広げても何も言わない**ので、与えるのは `Read` だけ。輪郭は
`scripts/verify.sh` が実物で確かめる:

```
S3_ANONYMOUS_READ=true      GET 200 / Range GET 206 / 一覧 403 / PUT 403 / DELETE 403 / 別 bucket 403
S3_ANONYMOUS_READ 未指定     GET 403
```

`S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` / `S3_BUCKET` の値に `"` と `\` は使えない。
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

| repo | 置き場所 | 版のずれを見る検査 | 特記 |
|---|---|---|---|
| browserhive | `seaweedfs/` | `pnpm run lint:seaweedfs-pin` | `S3_ANONYMOUS_READ=true` (replay が読む) |
| capture-ledger | `.upstream/seaweedfs/` | `pnpm run check:seaweedfs-pin` | bucket 名は `browserhive`（browserhive が置いたものを読む）。署名付き URL を発行する |
| wacz-validator | `seaweedfs/` | `pnpm run check:seaweedfs-pin` | `S3_INIT_ATTEMPTS=10`。匿名 Read は使わない |
