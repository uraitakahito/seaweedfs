---
title: クイックスタート
description: DNS ドメインを 1 度作り、store を起こし、宛先を知る。
---

## 一度だけの準備

project 名と同じ DNS ドメインを作る。マシンごとに 1 度だけで、`sudo` が要る。

```sh
sudo container system dns create crawler-storage
```

これで store が `seaweedfs.crawler-storage` としてプラットフォームの DNS に登録され、
**他のコンテナからも host からも**同じ綴りで引ける。

## 起こす・止める

submodule の中からでも同じ store が立つ（project 名も volume も同じ）ので、消費者の repo から
出なくてよい。

```sh
sh scripts/stack.sh up      # または  sh .upstream/seaweedfs/scripts/stack.sh up
sh scripts/stack.sh down
```

`stack.sh` は起こす前に 2 つを見る —— `container` と `container-compose` が PATH に居るか、
DNS ドメインが登録されているか。足りなければ名指しで止まる。

## 宛先

| 口 | コンテナから | host から | 用途 |
|---|---|---|---|
| S3 API | `http://seaweedfs.crawler-storage:8333` | `http://127.0.0.1:8333` | `aws` CLI。**普段はこちら** |
| Filer | `http://seaweedfs.crawler-storage:8888` | `http://127.0.0.1:8888` | ブラウザで中身を見る |
| Master | `:9333` | `http://127.0.0.1:9333` | `/dir/status` で状態を見る |

host 側から使うときは **`127.0.0.1` のほう**を選ぶ。macOS では、Apple 署名でないバイナリ
（node・grpcurl・aws）がコンテナの subnet に繋げない環境があり、DNS 名では届かないことがある。

成果物をブラウザで見るなら `http://127.0.0.1:8888/buckets/browserhive/`。

## bucket と鍵

bucket は `docker-compose.yml` の `S3_BUCKETS` に並んでいて、起動時に entrypoint が作る
（上限つきの再試行つき。順序を待つ init コンテナは無い）。**鍵は bucket 名と同じ綴り**で、
identity は bucket ごとに分かれている。詳しくは[設定](/ja/configuration/)。

次に読むもの: [運用](/ja/operations/)（消す・見る・リセット）、[消費者](/ja/consumers/)（どの repo が何を使うか）。
