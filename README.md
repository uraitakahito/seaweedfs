# seaweedfs

crawler の各 repo が共有する SeaweedFS。**store は 1 つだけ立て、3 つの repo がそれを見る。**
公式 image (`docker.io/chrislusf/seaweedfs`) をそのまま使い、entrypoint と bucket の初期化だけを
ここが持つ。配り方は git submodule。

## ドキュメント

立て方・設定・運用（消す・見る・リセット）・版の上げ方・消費者の一覧は、すべてドキュメントに:

- **日本語** — <https://uraitakahito.github.io/seaweedfs/ja/>
- **English** — <https://uraitakahito.github.io/seaweedfs/>

## すぐ立てる

```sh
sudo container system dns create crawler-storage   # マシンごとに 1 度だけ
sh scripts/stack.sh up
```

宛先は `http://seaweedfs.crawler-storage:8333`（host からは `http://127.0.0.1:8333`）。

## この repo に在るもの

| | |
|---|---|
| `docker-compose.yml` | **版の正。** image の 1 行が、すべての消費者の基準 |
| `etc/` | entrypoint（identity を env から組み立てる）と bucket の初期化 |
| `scripts/` | `stack.sh`（起動口）・`wipe.sh`・`verify.sh`（版を上げる前に回す）・`check-*.sh` |
| `docs-site/` | 上のドキュメントの原稿（Astro + Starlight） |

## 消費者

[BrowserHive](https://github.com/uraitakahito/browserhive)（`seaweedfs/`）・
[capture-ledger](https://github.com/uraitakahito/capture-ledger)（`.upstream/seaweedfs/`）・
[wacz-validator](https://github.com/uraitakahito/wacz-validator)（`seaweedfs/`）が submodule として
取り込んでいる。詳しくは[消費者](https://uraitakahito.github.io/seaweedfs/ja/consumers/)。
