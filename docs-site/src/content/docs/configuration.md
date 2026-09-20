---
title: Configuration
description: The three env vars, and how the per-bucket identities get built.
---

Configuration is the env in `docker-compose.yml`, and nothing else. There is no config file:
`etc/entrypoint.sh` assembles the identity JSON on the spot — if there is no reason to fork, no fork
happens.

| env | Required | Default | Effect |
|---|---|---|---|
| `S3_BUCKETS` | ✓ | — | the buckets to create, comma-separated. **The identity name and the keys are spelled the same** |
| `S3_ANONYMOUS_READ_BUCKETS` | | (none) | comma-separated buckets that give anonymous `Read:<bucket>` |
| `S3_INIT_ATTEMPTS` | | `30` | how many times bucket creation retries (per bucket) |

## The keys are the bucket name

One store serves several consumers, so identities are per bucket and `actions` is scoped to the
bucket (the `Read:<bucket>` form). Unscoped, one consumer's keys reach another consumer's bucket.
`scripts/verify.sh` checks those four against a real store — on someone else's bucket, listing is
`AccessDenied` and getting and writing are refused; your own bucket is writable.

## The shape of anonymous Read

`S3_ANONYMOUS_READ_BUCKETS` is there for readers that cannot hold credentials. browserhive's replay
service (a single nginx, which does not sign S3 requests) uses it to pass `/wacz/<key>` straight
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
