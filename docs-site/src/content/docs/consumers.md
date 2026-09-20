---
title: Consumers
description: Which repository uses what of this store, and what guards it.
---

This repository ships as a **git submodule**. No consumer keeps a store of its own; they all look at
the same one.

| repo | Where it sits | bucket | Anonymous Read | Guard |
|---|---|---|---|---|
| [BrowserHive](https://github.com/uraitakahito/browserhive) | `seaweedfs/` | `browserhive` | yes (replay passes `/wacz/` straight through) | `lint:store-name` |
| [capture-ledger](https://github.com/uraitakahito/capture-ledger) | `.upstream/seaweedfs/` | `browserhive` | yes | `check:store-name` |
| [wacz-validator](https://github.com/uraitakahito/wacz-validator) | `seaweedfs/` | `wacz-validator` | no | `check:store-name` |

browserhive and capture-ledger looking at **the same bucket** is deliberate: capture-ledger is the
side that reads the artifacts browserhive put there.

## What a consumer holds

- **The submodule, and nothing else.** No copy of the compose file (`container-compose` can read
  neither `include:` nor `extends:`, but the store's service is gone from the consumers altogether,
  so there is nothing left to copy)
- `store:wipe` — one line that empties its own bucket (it is `scripts/wipe.sh` underneath)
- `check:store-name` / `lint:store-name` — looks for a `seaweedfs.<project name>` left behind in
  docs or code. **Only one store is running**, so a per-repository spelling rots in the shape that
  does not work and does not fail the tests either

## Adding a bucket

Add one word to `S3_BUCKETS` in `docker-compose.yml`. The keys come out spelled like the bucket name
([Configuration](/configuration/)). If anonymous Read is needed, add it to
`S3_ANONYMOUS_READ_BUCKETS` as well — **grant `Read` and nothing else**.
