#!/bin/sh
# SeaweedFS を master + volume + filer + s3 の 1 プロセスとして立て、S3 の identity
# 設定を **その場で組み立てる**。
#
# テンプレートファイルを置いていないのは、identity の中身が配備ごとに違うため ——
# browserhive は replay に読ませるための anonymous が要り、wacz-validator は要らない。
# ファイルにすると、その差を表す手段が「fork する」しか無くなる。実際そうなっていて、
# 切り出す前は browserhive と wacz-validator (当時の waxlens) で 3 ファイルすべてが分岐していた。
#
# 設定は env だけで決まる:
#
#   S3_ACCESS_KEY_ID      (必須)
#   S3_SECRET_ACCESS_KEY  (必須)
#   S3_BUCKET             (必須) 作る bucket。identity 名も兼ねる
#   S3_ANONYMOUS_READ     既定 false。true で anonymous に Read:$S3_BUCKET を与える
#   S3_INIT_ATTEMPTS      既定 30。bucket 作成のリトライ回数
set -eu

: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"

# JSON は printf で組む —— この image には jq も envsubst も無い。だから値に " や \
# が入ると壊れる。しかも壊れ方が静かで、「資格情報が違う」形の失敗に化ける。先に落とす。
for value in "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY" "$S3_BUCKET"; do
  case "$value" in
    *'"'*|*'\'*)
      echo 'FATAL: S3 の値に " と \ は使えない (JSON を printf で組み立てるため)' >&2
      exit 1
      ;;
  esac
done

# 匿名 read。browserhive の replay サービスが、資格情報を持たずに /wacz/ を読むために
# 要る。**広げても何も言わない穴** なので、与えるのは Read だけ。
anonymous=""
if [ "${S3_ANONYMOUS_READ:-false}" = "true" ]; then
  anonymous=$(printf ',{"name":"anonymous","actions":["Read:%s"]}' "$S3_BUCKET")
fi

# /etc/seaweedfs は read-only で mount されるので、書き先は /tmp。
S3_CONFIG=/tmp/seaweedfs-s3.json
printf '{"identities":[{"name":"%s","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":["Admin","Read","Write","List","Tagging"]}%s]}\n' \
  "$S3_BUCKET" "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY" "$anonymous" > "${S3_CONFIG}"

# bucket の作成は server と並走させる。順序を面倒みるべき使い捨ての init コンテナは
# 別に無い —— 待つ仕事は init-bucket.sh のリトライループが全部やる。
/etc/seaweedfs/init-bucket.sh "$S3_BUCKET" localhost:9333 "${S3_INIT_ATTEMPTS:-30}" &

exec weed server \
  -dir=/data \
  -master.volumeSizeLimitMB=1024 \
  -filer \
  -s3 \
  -s3.config="${S3_CONFIG}"
