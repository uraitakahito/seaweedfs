---
title: seaweedfs
description: crawler の repo が共有する 1 つの SeaweedFS —— 設定・運用・消費者への配り方。
---

crawler の各 repo が共有するオブジェクトストア。**store は 1 つだけ立て、3 つの repo がそれを見る。**

この repo は設定を持ち、起動もここから行う。配り方は git submodule で、
[BrowserHive](https://github.com/uraitakahito/browserhive)・
[capture-ledger](https://github.com/uraitakahito/capture-ledger)・
[wacz-validator](https://github.com/uraitakahito/wacz-validator) が取り込んでいる。
