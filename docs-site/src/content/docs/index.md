---
title: seaweedfs
description: The one SeaweedFS the Web Capture repositories share — configuration, operations and how consumers vendor it.
---

The object store the [Web Capture](https://uraitakahito.github.io/capture-ledger/#web-capture) repositories share. **One store runs; three repositories use it.**

This repository holds the configuration and brings the store up. It is vendored as a git
submodule by [BrowserHive](https://github.com/uraitakahito/browserhive),
[capture-ledger](https://github.com/uraitakahito/capture-ledger) and
[wacz-validator](https://github.com/uraitakahito/wacz-validator).
