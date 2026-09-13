#!/bin/sh
# 消費者の compose が、この repo の compose と同じ SeaweedFS の image を使っているか。
#
# container-compose は include: も extends: も読めないので、service ブロックは各 repo に
# 写すしかない。写しがずれても何も落ちない —— 4.23 のまま残った写しは、上流 #9563
# (空にしたバケットが再起動で書けなくなる) を抱えた store を黙って立て続ける。だから
# 写しを直して回るのではなく、ずれを検査で落とす。
#
#   sh seaweedfs/scripts/check-pin.sh docker-compose.yml
#
# 比べるのは image の行だけ。2 つの版を書いた写しは、1 つに揃うまで落ちる。
set -eu

here="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "使い方: sh check-pin.sh <消費者の docker-compose.yml>" >&2
  exit 2
fi

pin() { grep -Eo 'chrislusf/seaweedfs:[^"[:space:]]+' "$1" | sort -u || true; }

want="$(pin "$here/docker-compose.yml")"
got="$(pin "$1")"

if [ -z "$want" ]; then
  echo "原本の docker-compose.yml に SeaweedFS の image が見つからない" >&2
  exit 2
fi
if [ "$got" != "$want" ]; then
  echo "SeaweedFS の image が原本とずれている: $1 は ${got:-（見つからない）}、原本は $want" >&2
  echo "原本の版を使うこと (版を上げるときは原本の scripts/verify.sh を回してから)。" >&2
  exit 1
fi
echo "seaweedfs pin: $want"
