---
title: Quickstart
description: Create the DNS domain once, bring the store up, and know where to point.
---

## One-time setup

Create a DNS domain named after the project. Once per machine, and it needs `sudo`.

```sh
sudo container system dns create crawler-storage
```

That registers the store with the platform's DNS as `seaweedfs.crawler-storage`, reachable **from
other containers and from the host** under the same spelling.

## Up and down

The same store comes up from inside a submodule (same project name, same volume), so there is no
need to leave the consumer's repository.

```sh
sh scripts/stack.sh up      # or  sh .upstream/seaweedfs/scripts/stack.sh up
sh scripts/stack.sh down
```

`stack.sh` looks at two things before it starts anything — whether `container` and
`container-compose` are on PATH, and whether the DNS domain is registered. If either is missing it
stops and names it.

## Addresses

| Port | From a container | From the host | Use |
|---|---|---|---|
| S3 API | `http://seaweedfs.crawler-storage:8333` | `http://127.0.0.1:8333` | the `aws` CLI. **Normally this one** |
| Filer | `http://seaweedfs.crawler-storage:8888` | `http://127.0.0.1:8888` | browsing the contents |
| Master | `:9333` | `http://127.0.0.1:9333` | `/dir/status` for its state |

From the host, pick **the `127.0.0.1` one**. On macOS there are machines where a binary that is not
Apple-signed (node, grpcurl, aws) cannot reach the containers' subnet — there the DNS name does not
get through.

To look at the artifacts in a browser: `http://127.0.0.1:8888/buckets/browserhive/`.

## Buckets and keys

The buckets are listed in `S3_BUCKETS` in `docker-compose.yml`, and the entrypoint creates them at
startup (with a bounded retry; there is no init container to wait on for ordering). **The keys are
spelled exactly like the bucket name**, and identities are per bucket. Details in
[Configuration](/configuration/).

Read next: [Operations](/operations/) (deleting, looking, resetting), [Consumers](/consumers/)
(which repository uses what).
