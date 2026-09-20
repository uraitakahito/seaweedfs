---
title: 消費者
description: どの repo がこの store の何を使い、何で見張っているか。
---

この repo は **git submodule** として配る。消費者は自分の store を持たず、同じ 1 つを見る。

| repo | 置き場所 | bucket | 匿名 Read | 見張り |
|---|---|---|---|---|
| [BrowserHive](https://github.com/uraitakahito/browserhive) | `seaweedfs/` | `browserhive` | 使う（replay が `/wacz/` を素通しする） | `lint:store-name` |
| [capture-ledger](https://github.com/uraitakahito/capture-ledger) | `.upstream/seaweedfs/` | `browserhive` | 使う | `check:store-name` |
| [wacz-validator](https://github.com/uraitakahito/wacz-validator) | `seaweedfs/` | `wacz-validator` | 使わない | `check:store-name` |

browserhive と capture-ledger が**同じ bucket**を見るのは意図的で、capture-ledger は
browserhive が置いた成果物を読む側だから。

## 消費者が持つもの

- **submodule だけ。** compose の写しは持たない（`container-compose` は `include:` も
  `extends:` も読めないが、store の service ごと消費者から無くしたので写す対象が無い）
- `store:wipe` —— 自分の bucket を空にする 1 行（中身は `scripts/wipe.sh`）
- `check:store-name` / `lint:store-name` —— docs やコードに `seaweedfs.<project 名>` が
  残っていないかを見る。**store は 1 つしか立っていない**ので、repo ごとの綴りは
  「動かないのに試験では落ちない」形で腐る

## bucket を増やすとき

`docker-compose.yml` の `S3_BUCKETS` に 1 語足す。鍵は bucket 名と同じ綴りになる
（[設定](/ja/configuration/)）。匿名 Read が要るなら `S3_ANONYMOUS_READ_BUCKETS` にも足す ——
**与えるのは `Read` だけ**。
