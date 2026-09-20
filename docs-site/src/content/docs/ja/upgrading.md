---
title: 版を上げる
description: 版の正は compose の 1 行。上げる前に verify.sh を回し、4.27 未満には戻さない。
---

版の正は `docker-compose.yml` の image の 1 行だけ。この頁の見本がそこからずれたら CI が落とす
（`scripts/check-doc-refs.sh` が `scripts/check-pin.sh` を呼ぶ）。

```yaml
    image: docker.io/chrislusf/seaweedfs:4.46
```

## 手順

1. `docker-compose.yml` とこの頁の見本の版を書き換える
2. **`scripts/verify.sh` を回す。** 消費者が頼っている挙動を、`etc/` の entrypoint をそのまま
   使う使い捨てのコンテナで 1 つずつ確かめる —— 資格情報での読み書き、匿名 Read の輪郭、
   誤った秘密鍵、署名付き URL、鍵の長さの上限（255 バイト）、bucket の分離、空にして
   再起動した後の書き込み。終了コードは赤の数
3. タグを打ち、各消費者で submodule を上げる。dev の store は作り直す

```sh
sh scripts/verify.sh          # docker-compose.yml が固定している版
sh scripts/verify.sh 4.23     # 版を指定する
```

`verify.sh` が要るのは `container`（Apple Container）、`aws`（AWS CLI v2）、`curl`。S3 は
`127.0.0.1:18333`（`VERIFY_PORT` で変えられる）に publish するので、他のスタックが動いていても
回せる。終わると（途中で落ちても）コンテナと volume を消す。

## 4.27 未満に戻さないこと

4.26 以前は、最後の記録が削除のボリュームを起動時の検査が壊れていると誤判定し、読み取り専用で
読み込む（上流 [#9563](https://github.com/seaweedfs/seaweedfs/issues/9563)、4.27 で修正）。
バケット用のボリュームが 1 本しか無いスタックでは、**バケットを空にして再起動しただけで
書き込みが止まる**。`sh scripts/verify.sh 4.23` はその 1 行だけが赤になる。
