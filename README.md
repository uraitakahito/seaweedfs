# seaweedfs

crawler の各 repo が共有する SeaweedFS の起動設定。**submodule として使う**。

公式 image (`docker.io/chrislusf/seaweedfs`) をそのまま使い、entrypoint と bucket の
初期化だけをここが持つ。image は焼かない。

## なぜ切り出したか

同じ 2 ファイルが browserhive と waxlens に別々に置かれ、**3 ファイルすべてが分岐して
いた**。しかも waggle は自分の写しを持たず、`browserhive/etc/seaweedfs` を submodule
越しに mount していた —— object store が欲しいだけなのに browserhive 全体に依存する形
になっていた。

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
(実測: どちらもデコードに失敗する)。写した先がずれても誰も気づかないので、迷ったら
ここを見ること。

```yaml
  seaweedfs:
    image: docker.io/chrislusf/seaweedfs:4.23
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
のに使う。**この穴は広げても何も言わない**ので、与えるのは `Read` だけ。実測した輪郭:

```
S3_ANONYMOUS_READ=true      GET 200 / LIST 403 / PUT 403 / DELETE 403
S3_ANONYMOUS_READ 未指定     GET 403
```

`S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` / `S3_BUCKET` の値に `"` と `\` は使えない。
identity JSON を `printf` で組み立てているため (image に `jq` も `envsubst` も無い)。
そのまま通すと「資格情報が違う」形の静かな失敗になるので、起動時に FATAL で落とす。

## 消費者

| repo | 置き場所 | 特記 |
|---|---|---|
| browserhive | `seaweedfs/` | `S3_ANONYMOUS_READ=true` (replay が読む) |
| waggle | `.upstream/seaweedfs/` | proto のために browserhive も持つが、object store のためには持たない |
| waxlens | `seaweedfs/` | `S3_INIT_ATTEMPTS=10` |
