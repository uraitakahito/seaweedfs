#!/bin/sh
# bucket の中身だけを空にする。**開発中にいちばん使う操作。**
#
#   sh scripts/wipe.sh browserhive                                        # 共有 store (127.0.0.1:8333)
#   sh scripts/wipe.sh browserhive http://seaweedfs.crawler-storage:8333  # 名前で指す
#   sh scripts/wipe.sh browserhive http://127.0.0.1:18333                 # 使い捨ての store (verify.sh の既定)
#   sh scripts/wipe.sh browserhive "" --dryrun                            # 3 つ目以降は aws へ渡る
#
# bucket は消さない —— 作り直すと identity の設定と食い違う瞬間ができる。空にするだけなら
# 4.27 以降は安全 (4.26 以前は、空にした bucket が再起動で書けなくなる。上流 #9563)。
#
# 鍵は bucket 名と同じ。この repo の identity の約束で、消費者 3 つとも従っている
# (docs/operations.ja.md の表)。
set -eu

bucket="${1:?使い方: wipe.sh <bucket> [endpoint] [aws の追加引数...]}"
endpoint="${2:-http://127.0.0.1:8333}"
[ "$endpoint" = "" ] && endpoint=http://127.0.0.1:8333
[ "$#" -ge 2 ] && shift 2 || shift 1

# **AWS_PROFILE は外す。** 設定されていると上の環境変数より静かに勝ち、意図しない鍵
# (本物の AWS のものを含む) で話す。エラーは「資格情報が違う」としか言わない。
unset AWS_PROFILE

echo "空にする: s3://$bucket/  (${endpoint})"
AWS_ENDPOINT_URL_S3="$endpoint" AWS_REGION="${AWS_REGION:-us-east-1}" \
AWS_ACCESS_KEY_ID="$bucket" AWS_SECRET_ACCESS_KEY="$bucket" \
  aws s3 rm "s3://$bucket/" --recursive "$@"
