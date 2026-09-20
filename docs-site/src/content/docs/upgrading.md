---
title: Upgrading
description: The version of record is one compose line. Run verify.sh before moving it, and never go back below 4.27.
---

The version of record is one line: the image in `docker-compose.yml`. If the sample on this page
drifts from it, CI fails (`scripts/check-doc-refs.sh` calls `scripts/check-pin.sh`).

```yaml
    image: docker.io/chrislusf/seaweedfs:4.46
```

## Steps

1. Change the version in `docker-compose.yml` and in the sample on this page
2. **Run `scripts/verify.sh`.** It checks the behaviours the consumers depend on one at a time, in
   throwaway containers that use `etc/`'s entrypoint as it stands — reading and writing with
   credentials, the shape of anonymous Read, a wrong secret key, presigned URLs, the key length
   limit (255 bytes), bucket isolation, and writing after the bucket has been emptied and the store
   restarted. The exit code is the number of reds
3. Tag it, and bump the submodule in each consumer. Recreate the dev store

```sh
sh scripts/verify.sh          # the version docker-compose.yml pins
sh scripts/verify.sh 4.23     # a version you name
```

`verify.sh` needs `container` (Apple Container), `aws` (AWS CLI v2) and `curl`. It publishes S3 on
`127.0.0.1:18333` (`VERIFY_PORT` changes it), so it runs with other stacks up. When it is done —
including when it dies partway — it removes the container and the volume.

## Do not go back below 4.27

On 4.26 and earlier, the startup check misreads a volume whose last record is a delete as corrupt
and loads it read-only (upstream [#9563](https://github.com/seaweedfs/seaweedfs/issues/9563), fixed
in 4.27). On a stack with only one volume behind the bucket, **emptying the bucket and restarting is
by itself enough to stop writes**. `sh scripts/verify.sh 4.23` goes red on that one line and nothing
else.
