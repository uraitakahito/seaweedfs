# SeaweedFS operations

Hands-on page for a store brought up with this repo's configuration. The Japanese version is
[operations.ja.md](operations.ja.md). How to start the store and configure it is in the
[README](../README.md); the design of the artifact store — pointing at an external S3, addressing
styles, what the region is for — lives in each consumer's own docs.

The one you will reach for most is emptying the artifacts that pile up as you re-run captures.
**This line is all of it.**

```sh
sh scripts/wipe.sh <bucket>
```

Everything else on this page is around that.

## Pointing at your store

The commands below take a `<bucket>` and an endpoint. Per consumer:

| Consumer | Bucket and keys | Endpoint |
|---|---|---|
| browserhive / capture-ledger | `browserhive` | `http://seaweedfs.crawler-storage:8333` |
| wacz-validator | `wacz-validator` | `http://seaweedfs.crawler-storage:8333` |

**The keys are the bucket name** (both `accessKey` and `secretKey`). Identities are per bucket and
cannot touch anything outside their own. For a throwaway store (a consumer's `--own-store`), read
the endpoint as `http://seaweedfs.<project>:8333`, where `<project>` is that consumer's compose
project name — which doubles as the DNS domain.

```sh
export AWS_ACCESS_KEY_ID=browserhive
export AWS_SECRET_ACCESS_KEY=browserhive
export AWS_ENDPOINT_URL_S3=http://seaweedfs.crawler-storage:8333
export AWS_REGION=us-east-1
```

> [!CAUTION]
> **Always set the endpoint.** Forget `--endpoint-url` (or `AWS_ENDPOINT_URL_S3`) and `aws` talks to
> **the real AWS**, with whatever credentials your `~/.aws/config` supplies. If you run something as
> irreversible as `s3 rm --recursive` routinely, pinning the endpoint in the environment is safer
> than remembering a flag every time.

> [!CAUTION]
> **A set `AWS_PROFILE` silently outranks the variables above.** You end up talking with keys you did
> not mean to use, and the error only ever says the credentials are wrong. Either `unset AWS_PROFILE`
> or use `scripts/wipe.sh`, which unsets it for you.

The region does not need to be set. SeaweedFS ignores the value, but SigV4 always carries one — on a
machine with nothing in `~/.aws/config`, add `AWS_REGION=us-east-1`.

The commands use the [AWS CLI](https://docs.aws.amazon.com/cli/) (`brew install awscli`). Anything
that speaks S3 works just as well — `s5cmd`, `mc`, and friends.

## Two ways in

The store runs master, volume, filer, and S3 in one process. Two ports are reachable from outside.

| Port | Address | Use |
|---|---|---|
| S3 API | `:8333` | the `aws` CLI. **Normally this one** |
| Filer | `:8888` | browsing the contents |

The shared store also publishes `8333`, `8888` and `9333` on `127.0.0.1`, so `http://127.0.0.1:8333`
reaches the same place. **Throwaway stores publish nothing** — the platform DNS name resolves from
the host too, so there is nothing to expose and no port to collide.

## Delete every file

Empty the bucket while keeping the bucket itself. **The operation you will use most during
development.**

```sh
sh scripts/wipe.sh browserhive                         # the shared store
sh scripts/wipe.sh browserhive http://127.0.0.1:18333  # a throwaway store (verify.sh's default port)
```

Only the artifacts go; the bucket and SeaweedFS's own state stay. The next capture writes straight
into it with nothing to recreate. To see what would go without going through with it, add
`--dryrun` (extra arguments are passed to `aws`).

```sh
sh scripts/wipe.sh browserhive "" --dryrun
```

Spelled out by hand:

```sh
aws s3 rm s3://browserhive/ --recursive
```

> [!NOTE]
> About **0.7 s** for 730 objects (the state after a few e2e rounds). `aws` batches the deletes, so
> this does not become a wait as the count grows.

### Confirm it went

```sh
aws s3 ls s3://browserhive/ --recursive | wc -l   # 0
aws s3 ls                                          # the bucket is still there
```

## Look at the contents

```sh
# top level
aws s3 ls s3://browserhive/

# everything, and the count
aws s3 ls s3://browserhive/ --recursive | wc -l

# read one out (browserhive's .result.json is the manifest)
aws s3 cp s3://browserhive/<key>.result.json - | jq .

# pull one down
aws s3 cp s3://browserhive/<key>.wacz ./out.wacz
```

For browsing, the filer is quicker.

```
http://seaweedfs.crawler-storage:8888/buckets/browserhive/
```

## weed shell — SeaweedFS's own CLI

What the S3 API cannot show you — filer metadata, actual disk usage — comes from `weed shell`. It is
an interactive shell, but piping into it works for one-offs. The shared store's container is
`seaweedfs.crawler-storage`.

```sh
printf 'fs.du /buckets/browserhive\n' | container exec -i seaweedfs.crawler-storage weed shell
```

The useful ones:

| Command | What it tells you |
|---|---|
| `fs.ls /buckets` | the buckets |
| `fs.du /buckets/<bucket>` | the logical size actually in use |
| `s3.bucket.list` | buckets with their size / chunk |
| `fs.rm -r <path>` | recursive delete, bypassing the S3 API |

> [!CAUTION]
> **`s3.bucket.list`'s size cannot be trusted.** Right after deleting every object it may still
> report something like `size:1318264` — while `fs.du` reports `logical size: 5` at the same moment.
> That number does not subtract deletions promptly. **For real usage, read `fs.du`.**

## Reset the store's state

For when SeaweedFS itself is suspect rather than its contents — corrupted metadata, mismatched
credentials, a bucket that never got created. **Not for routine cleanup**; `wipe.sh` above covers
that.

```sh
sh scripts/stack.sh down
container rm seaweedfs.crawler-storage
container volume rm crawler-storage_seaweedfs-data   # confirm the name with container volume ls
sh scripts/stack.sh up
```

`down` stops the containers but does not remove them, and a volume that a stopped container still
holds cannot be deleted (`volume … is currently in use`) — hence the `container rm` first.

Dropping the volume takes the buckets and SeaweedFS's metadata with it. The next `up` recreates the
volume and the entrypoint recreates the buckets — `etc/init-bucket.sh` has a retry loop that waits
for the master, so there is no ordering to arrange.

**Deleting artifacts leaves the ledger rows that point at them.** Opening such a row from
capture-ledger's picker gets a 404 from replay. When you recreate the store, recreate the consumer's
database too.

## When something is wrong

| Symptom | Where to look |
|---|---|
| `aws` gets connection refused | is the store up (`seaweedfs.crawler-storage` in `container ls`)? `sh scripts/stack.sh up` |
| `403` | do the keys match the bucket name? Identities are per bucket and cannot reach another one |
| `NoSuchBucket` | the entrypoint has not finished creating it; wait on `aws s3 ls` |
| Buckets you do not recognise | the endpoint is not taking effect — you are looking at the real AWS. Suspect `AWS_PROFILE` too |
| Deleting does not free space | read `fs.du`, not `s3.bucket.list` |
| Anonymous read gets 403 | is that bucket in `S3_ANONYMOUS_READ_BUCKETS`? (listing is always 403 for anonymous) |
