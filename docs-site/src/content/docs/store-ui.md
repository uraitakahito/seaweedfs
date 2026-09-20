---
title: Finding artifacts
description: A page that lists what was captured, newest first. One file, served by the filer.
---

A page for looking at captured artifacts **newest first**. 日本語版は
[日本語版](/ja/store-ui/). Bringing the store up is in [Quickstart](/quickstart/); deleting,
counting and `weed shell` are in [Operations](/operations/).

```
http://127.0.0.1:8888/ui/index.html
```

`sh scripts/stack.sh up` puts it there on every start, so there is nothing to set up.

## Why a page is needed at all

**S3 listings only come back in name order.** `ListObjectsV2` has no sort parameter; it is
specified to return keys in lexicographical order. The filer's own page and `weed admin` are the
same — neither can order by date (`weed admin`'s sort parameters have no effect, and the official
wiki's claim that its file browser can "sort by name, size, or modification date" does not match
the implementation).

Ordering by date is therefore **never available from the server**, and has to happen on the
receiving side. This page reads the filer's JSON and re-orders it by time. **No extra container, no
extra process.**

## What it shows

| Column | Contents |
|---|---|
| Time | the newest `Mtime` of the capture, in the local time zone. This is what it sorts on |
| Label | the labels and correlation id carried in the key |
| Artifacts | `wacz` / `png` / `html` / `result.json` … click to open |
| Size | the total this capture wrote |
| taskId | first 8 characters (hover for all of it) |

**One row is one capture.** A single capture writes several objects, so the page reads the key
shape `{taskId}_{correlationId}[_{label}]*.{extension}` and groups by taskId. Keys that do not fit
that shape are listed one per row instead (**a display-only convention; no correctness rides on
it**).

Every `.wacz` gets a ▶ replay link. It points at the self-hosted
[ReplayWeb.page](https://replayweb.page/) (the `replay` profile of
[BrowserHive](https://github.com/uraitakahito/browserhive)), which has **exactly one bucket
upstream** — so the link only appears for `browserhive`.

## e2e is hidden by default

An e2e run leaves hundreds of artifacts behind, and they bury the ones you took yourself. Measured
here: **266 of 274 captures were from e2e**, leaving 8 rows once they are hidden.

Press "e2e を隠す" to show them again. **The page only hides; it removes nothing.** Removing is
`scripts/wipe.sh`, in [Operations](/operations/).

The filter (press `/` to jump to it) matches keys, labels and task ids alike. Filtering by kind and
sorting by time or size are on the same row.

## What the address accepts

| Parameter | Default | What it changes |
|---|---|---|
| `?bucket=` | the first bucket | which bucket is selected on open |
| `?filer=` | same origin | where the filer is (needed when opening over `file://`) |
| `?replay=` | `https://replay.browserhive` | where ▶ replay points; empty hides it |
| `?replayBucket=` | `browserhive` | which bucket gets a ▶ replay link |

Opening `ui/index.html` straight from a checkout works too: the filer answers with
`Access-Control-Allow-Origin: *`, so a `file://` page can read it (measured).

## Where it lives

`scripts/ui.sh` uploads it, and it lands on the filer at `/ui/index.html` — **outside the S3
buckets**.

- inside a bucket, a page meant to make artifacts easier to find would show up among them
- inside a bucket, `scripts/wipe.sh` would delete it along with everything else
- served by the filer, the page and the JSON share an origin, so no browser restriction applies

> [!CAUTION]
> **Do not expose this page.** There is no authentication; it relies on the filer being published
> to `127.0.0.1` only, as `docker-compose.yml` does.
>
> For the same reason it **cannot live on the documentation site**. The filer does not answer
> preflights with `Access-Control-Allow-Private-Network`, so an https page reaching for
> `127.0.0.1` is blocked by Chrome's Private Network Access (measured).

## Changing it

`ui/index.html` is a single file with no dependencies and no build step. Edit it and put it back.

```sh
sh scripts/stack.sh up     # overwritten on every up
sh scripts/ui.sh           # just the page
```

## When something looks wrong

| Symptom | Where to look |
|---|---|
| "filer から読めませんでした" | is the store up (`sh scripts/stack.sh up`)? Opened over `file://`? Add `?filer=http://…:8888` |
| only a handful of rows | "e2e を隠す" is on. Press it |
| ▶ replay returns 502 | replay is not running (BrowserHive's `replay` profile) |
| no ▶ replay at all | you are looking at a bucket other than `browserhive` |
| the page looks stale | `sh scripts/stack.sh up` puts the current one back |
