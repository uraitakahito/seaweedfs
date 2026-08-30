#!/bin/sh
# bucket を作る。回数を区切って再試行する。
#
# entrypoint.sh が `weed server` と並走させる形で背後に起動する —— master が
# 上がるのを待つ仕事は、下のループが全部やる。
#
# `weed shell` は master に gRPC で届く。gRPC の口は HTTP の口より少し遅れて
# 接続を受け付けることがあり、その間 `weed shell` は
# "passthrough: received empty target" と言いながら **終了コード 0 で終わる**。
# 終了コードだけを信じられないので、試行のたびに bucket を列挙し直して
# 最終状態のほうを確かめる。
#
# Usage:  init-bucket.sh <bucket-name> [<master-host:port>] [<attempts>]
set -eu

BUCKET="${1:?bucket name required}"
MASTER="${2:-localhost:9333}"
MAX_ATTEMPTS="${3:-30}"

attempt=0
while [ "${attempt}" -lt "${MAX_ATTEMPTS}" ]; do
  attempt=$((attempt + 1))
  echo "s3.bucket.create -name ${BUCKET}" | weed shell -master="${MASTER}" 2>&1 || true
  if echo "s3.bucket.list" | weed shell -master="${MASTER}" 2>/dev/null \
      | awk '{print $1}' | grep -q "^${BUCKET}$"; then
    echo "Bucket ${BUCKET} ready."
    exit 0
  fi
  echo "attempt ${attempt}: bucket not yet created, retrying in 1s..."
  sleep 1
done

echo "ERROR: bucket ${BUCKET} could not be created after ${MAX_ATTEMPTS} attempts" >&2
exit 1
