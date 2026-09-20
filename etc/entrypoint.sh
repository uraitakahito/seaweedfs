#!/bin/sh
# SeaweedFS を master + volume + filer + s3 の 1 プロセスとして立て、S3 の identity
# 設定を **その場で組み立てる**。
#
# テンプレートファイルを置いていないのは、identity の中身が配備ごとに違うため ——
# browserhive は replay に読ませるための anonymous が要り、wacz-validator は要らない。
# ファイルにすると、その差を表す手段が「fork する」しか無くなる。実際そうなっていて、
# 切り出す前は browserhive と wacz-validator (当時の waxlens) で 3 ファイルすべてが分岐していた。
#
# ## bucket は複数
#
# **1 つの store を複数の消費者が使う。** bucket ごとに identity を 1 つ作り、鍵は bucket
# 名と同じにする。`actions` は **bucket で絞る** (`Read:<bucket>`) —— 絞らないと、ある
# 消費者の鍵で別の消費者の bucket まで触れてしまう。実測: 絞った形では、他人の bucket は
# 一覧が AccessDenied、取得が 403 になる。
#
# 設定は env だけで決まる:
#
#   S3_BUCKETS                 (必須) 作る bucket をカンマ区切りで。identity 名と鍵も同じ綴り
#   S3_ANONYMOUS_READ_BUCKETS  匿名 Read を与える bucket をカンマ区切りで (既定は与えない)
#   S3_INIT_ATTEMPTS           既定 30。bucket 作成のリトライ回数 (bucket ごと)
set -eu

: "${S3_BUCKETS:?S3_BUCKETS is required (カンマ区切りの bucket 名)}"

# JSON は printf で組む —— この image には jq も envsubst も無い。だから値に " や \
# が入ると壊れる。しかも壊れ方が静かで、「資格情報が違う」形の失敗に化ける。先に落とす。
case "${S3_BUCKETS}${S3_ANONYMOUS_READ_BUCKETS:-}" in
  *'"'*|*'\'*)
    echo 'FATAL: bucket 名に " と \ は使えない (JSON を printf で組み立てるため)' >&2
    exit 1
    ;;
esac

# 匿名 Read を与える bucket。browserhive の replay サービスが、資格情報を持たずに /wacz/ を
# 読むために要る。**広げても何も言わない穴** なので、与えるのは Read だけ。一覧は与えない。
anonymous_for() {
  for allowed in $(echo "${S3_ANONYMOUS_READ_BUCKETS:-}" | tr ',' ' '); do
    [ "$allowed" = "$1" ] && return 0
  done
  return 1
}

identities=""
anonymous=""
for bucket in $(echo "$S3_BUCKETS" | tr ',' ' '); do
  identities="${identities}${identities:+,}$(printf \
    '{"name":"%s","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":["Admin:%s","Read:%s","Write:%s","List:%s","Tagging:%s"]}' \
    "$bucket" "$bucket" "$bucket" "$bucket" "$bucket" "$bucket" "$bucket" "$bucket")"
  if anonymous_for "$bucket"; then
    anonymous="${anonymous}${anonymous:+,}$(printf '"Read:%s"' "$bucket")"
  fi
  # bucket の作成は server と並走させる。順序を面倒みるべき使い捨ての init コンテナは
  # 別に無い —— 待つ仕事は init-bucket.sh のリトライループが全部やる。
  /etc/seaweedfs/init-bucket.sh "$bucket" localhost:9333 "${S3_INIT_ATTEMPTS:-30}" &
done

[ -n "$anonymous" ] && identities="${identities},$(printf '{"name":"anonymous","actions":[%s]}' "$anonymous")"

# /etc/seaweedfs は read-only で mount されるので、書き先は /tmp。
S3_CONFIG=/tmp/seaweedfs-s3.json
printf '{"identities":[%s]}\n' "$identities" > "${S3_CONFIG}"

exec weed server \
  -dir=/data \
  -master.volumeSizeLimitMB=1024 \
  -filer \
  -s3 \
  -s3.config="${S3_CONFIG}"
