---
title: Configuration
description: The three env vars, and how the per-bucket identities get built.
---

Configuration is the env in `docker-compose.yml`, and nothing else. There is no config file:
`etc/entrypoint.sh` assembles the identity JSON on the spot — if there is no reason to fork, no fork
happens. Only the capacity (next section) is fixed in the entrypoint rather than exposed as env.

| env | Required | Default | Effect |
|---|---|---|---|
| `S3_BUCKETS` | ✓ | — | the buckets to create, comma-separated. **The identity name and the keys are spelled the same** |
| `S3_ANONYMOUS_READ_BUCKETS` | | (none) | comma-separated buckets that give anonymous `Read:<bucket>` |
| `S3_INIT_ATTEMPTS` | | `30` | how many times bucket creation retries (per bucket) |

## Capacity

`etc/entrypoint.sh` fixes two settings. No consumer has a reason to differ, so they are not env.

| Setting | Value | SeaweedFS default | Effect |
|---|---|---|---|
| `-volume.max` | `64` | `8` | the maximum number of volumes. One volume is 1 GiB (`-master.volumeSizeLimitMB=1024`) |
| `WEED_MASTER_VOLUME_GROWTH_COPY_1` | `1` | `7` | how many volumes to add at a time |

With the defaults, the default collection takes 7 volumes right after startup and the bucket is left
with 1. When that one fills up, writes stop with `500 InternalError`.

- **To widen:** recreate the container with `sh scripts/stack.sh up`. The named volume keeps its contents
- **How it reverts:** running `up` from an older entrypoint silently returns to 8. Consumers bump the submodule first
- **To read it:** `Topology.Max`, `Free`, and `Layouts[].writables` from `curl -s http://127.0.0.1:9333/dir/status`
- **What checks it:** `scripts/verify.sh` reads the maximum and how many volumes the first PUT adds

## The keys are the bucket name

One store serves several consumers, so identities are per bucket and `actions` is scoped to the
bucket (the `Read:<bucket>` form). Unscoped, one consumer's keys reach another consumer's bucket.
`scripts/verify.sh` checks those four against a real store — on someone else's bucket, listing is
`AccessDenied` and getting and writing are refused; your own bucket is writable.

## The shape of anonymous Read

`S3_ANONYMOUS_READ_BUCKETS` is there for readers that cannot hold credentials.
[replayweb-server](https://github.com/uraitakahito/replayweb-server) (a small Node server, which does
not sign S3 requests) uses it to pass `/wacz/<key>` straight
through to the browser. **Nothing says anything when this hole is widened**, so grant `Read` and
nothing else. `scripts/verify.sh` checks the shape against a real store:

```
granted anonymous    GET 200 / Range GET 206 / list 403 / PUT 403 / DELETE 403 / another bucket 403
not granted          GET 403
```

## Bucket name restrictions

`"` and `\` cannot be used in a bucket name, because the identity JSON is assembled with `printf`
(the image has neither `jq` nor `envsubst`). Letting one through becomes a quiet failure shaped like
"wrong credentials", so it dies FATAL at startup.
