#!/bin/sh
# この版の SeaweedFS が、crawler の各 repo が頼っている約束を守るかを実物に訊く。
#
# 版を上げるときに回す。compose の版を書き換えただけでは、何が変わったかは分からない ——
# 4.23 → 4.46 のリリースノートには S3 の認証と匿名アクセスの変更が 20 近く並び、読むだけ
# では私たちの設定に効くかが決まらなかった。だから etc/ の entrypoint をそのまま使う
# 使い捨てのコンテナを立て、頼っている挙動を 1 つずつ確かめる。
#
#   scripts/verify.sh          # docker-compose.yml が固定している版
#   scripts/verify.sh 4.23     # 版を指定する (4.23 では「空にして再起動」の行だけが赤になる)
#
# 要るもの: container (Apple Container)、aws (AWS CLI v2)、curl。
# S3 は 127.0.0.1 の VERIFY_PORT (既定 18333) に publish する —— DNS のドメインにも、
# 動いている他のスタックの 8333 にも依らない。終われば (途中で落ちても) コンテナと
# volume を消す。終了コードは赤の数。
set -eu

here="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tag="${1:-$(grep -Eo 'chrislusf/seaweedfs:[^"[:space:]]+' "$here/docker-compose.yml" | head -n 1 | cut -d: -f2)}"
port="${VERIFY_PORT:-18333}"
name="seaweedfs-verify-$(printf '%s' "$tag" | tr -c 'A-Za-z0-9' '-')"
bucket=verify
# 2 つ目の bucket。**共有 store の要**は「ある消費者の鍵で、他人の bucket を触れないこと」。
other=verify-other
work="$(mktemp -d)"
failed=0

for tool in container aws curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "verify.sh: $tool が見つからない" >&2; exit 2; }
done

# 鍵は bucket 名と同じ (entrypoint.sh の約束)。
export AWS_ACCESS_KEY_ID="$bucket" AWS_SECRET_ACCESS_KEY="$bucket" AWS_REGION=us-east-1
# AWS_PROFILE が設定されていると、上の環境変数より静かに勝つ。
unset AWS_PROFILE || true
export AWS_ENDPOINT_URL="http://127.0.0.1:$port"
s3="$AWS_ENDPOINT_URL"

discard() {
  container rm -f "$name" >/dev/null 2>&1 || true
  container volume delete "$name-data" >/dev/null 2>&1 || true
}
trap 'discard; rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

expect() {
  if [ "$2" = "$3" ]; then
    printf '  ok    %s: %s\n' "$1" "$3"
  else
    printf '  FAIL  %s: 期待 %s / 実際 %s\n' "$1" "$2" "$3"
    failed=$((failed + 1))
  fi
}

# 引数は匿名 Read を与える bucket の一覧 (空なら与えない)。消費者の 2 つの形
# (browserhive / capture-ledger は与える、wacz-validator は与えない) を両方確かめる。
# bucket は常に 2 つ作る —— 1 つでは「他人の bucket に触れない」を確かめられない。
start() {
  discard
  container volume create "$name-data" >/dev/null
  container run -d --name "$name" -p "127.0.0.1:$port:8333" \
    -e "S3_BUCKETS=$bucket,$other" \
    -e "S3_ANONYMOUS_READ_BUCKETS=$1" \
    -v "$here/etc:/etc/seaweedfs:ro" -v "$name-data:/data" \
    --entrypoint /etc/seaweedfs/entrypoint.sh \
    "docker.io/chrislusf/seaweedfs:$tag" >/dev/null 2>&1
}

# bucket が作られ、S3 が署名付きの一覧に答えるまで待つ。
wait_ready() {
  i=0
  while [ "$i" -lt 120 ]; do
    if aws s3 ls "s3://$bucket/" --cli-connect-timeout 2 --cli-read-timeout 5 >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  echo "verify.sh: 120 秒待っても S3 が答えない" >&2
  container logs "$name" 2>&1 | tail -n 20 >&2
  exit 2
}

put() {
  if aws s3 cp "$work/obj.txt" "s3://$bucket/$1" --cli-read-timeout 20 >/dev/null 2>&1; then
    echo ok
  else
    echo no
  fi
}

# 署名を付けずに素で叩く。replay の nginx がやっているのと同じこと。
anon() {
  method="$1"
  path="$2"
  shift 2
  curl -s -o /dev/null -w '%{http_code}' -m 10 -X "$method" "$@" "$s3/$path"
}

repeat() {
  out=""
  i=0
  while [ "$i" -lt "$2" ]; do
    out="$out$1"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

printf 'hello' > "$work/obj.txt"
echo "chrislusf/seaweedfs:$tag"

echo "── 匿名 Read を与えた形 (S3_ANONYMOUS_READ_BUCKETS=$bucket)"
start "$bucket"
wait_ready
expect "資格情報で PUT" ok "$(put a/obj.txt)"
expect "資格情報で GET" hello "$(aws s3 cp "s3://$bucket/a/obj.txt" - 2>/dev/null || true)"
expect "資格情報で一覧" 1 "$(aws s3 ls "s3://$bucket/a/" 2>/dev/null | wc -l | tr -d ' ')"
expect "匿名 GET" 200 "$(anon GET "$bucket/a/obj.txt")"
expect "匿名 Range GET" 206 "$(anon GET "$bucket/a/obj.txt" -H 'Range: bytes=0-1')"
expect "匿名 一覧" 403 "$(anon GET "$bucket/")"
expect "匿名 書き" 403 "$(anon PUT "$bucket/anon.txt" --data-binary x)"
expect "匿名 消し" 403 "$(anon DELETE "$bucket/a/obj.txt")"
expect "匿名 別 bucket" 403 "$(anon GET "$other/x")"
expect "匿名で消そうとした後も残る" hello "$(aws s3 cp "s3://$bucket/a/obj.txt" - 2>/dev/null || true)"
expect "誤った秘密鍵で署名した GET" SignatureDoesNotMatch \
  "$(AWS_SECRET_ACCESS_KEY=definitely-not-the-key aws s3api get-object --bucket "$bucket" --key a/obj.txt "$work/out" 2>&1 | grep -o SignatureDoesNotMatch | head -n 1 || true)"
# **bucket の分離。** 共有 store では、これが崩れると 1 つの鍵で全部が見える。
expect "他人の bucket を一覧" AccessDenied \
  "$(aws s3 ls "s3://$other/" 2>&1 | grep -o AccessDenied | head -n 1 || true)"
expect "他人の bucket に書く" no \
  "$(aws s3 cp "$work/obj.txt" "s3://$other/x.txt" >/dev/null 2>&1 && echo ok || echo no)"
expect "他人の鍵で自分の bucket を読む" no \
  "$(AWS_ACCESS_KEY_ID="$other" AWS_SECRET_ACCESS_KEY="$other" \
     aws s3 cp "s3://$bucket/a/obj.txt" - >/dev/null 2>&1 && echo ok || echo no)"
expect "他人の鍵で自分の bucket には書ける" ok \
  "$(AWS_ACCESS_KEY_ID="$other" AWS_SECRET_ACCESS_KEY="$other" \
     aws s3 cp "$work/obj.txt" "s3://$other/own.txt" >/dev/null 2>&1 && echo ok || echo no)"

url="$(aws s3 presign "s3://$bucket/a/obj.txt" --expires-in 120 2>/dev/null || true)"
expect "署名付き URL で GET" 200 "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$url")"

# 鍵の上限はバイト数。browserhive の ARTIFACT_NAME_MAX_BYTES (255) がこの境界に立っている。
expect "鍵 255 バイト" ok "$(put "$(repeat k 255)")"
expect "鍵 256 バイト" no "$(put "$(repeat k 256)")"
expect "日本語の鍵 254 バイト" ok "$(put "$(repeat あ 84)kk")"
expect "日本語の鍵 257 バイト" no "$(put "$(repeat あ 85)kk")"

# 上流 #9563: バケットを空にして再起動すると、最後の記録が削除のボリュームを起動時の検査が
# 壊れていると誤判定し、読み取り専用にする (4.23)。バケット用のボリュームが 1 本しか無い
# スタックでは、それで書き込みが止まる。
aws s3 rm "s3://$bucket/" --recursive >/dev/null 2>&1 || true
container stop "$name" >/dev/null 2>&1
container start "$name" >/dev/null 2>&1
wait_ready
expect "空にして再起動: 書き込み対象から外れたボリューム" 0 "$(container logs "$name" 2>&1 | grep -c 'remove from writable' || true)"
expect "空にして再起動: その後の PUT" ok "$(put after-restart.txt)"

echo "── 匿名 Read を与えない形 (S3_ANONYMOUS_READ_BUCKETS 未指定)"
start ""
wait_ready
expect "資格情報で PUT" ok "$(put a/obj.txt)"
expect "匿名 GET" 403 "$(anon GET "$bucket/a/obj.txt")"

if [ "$failed" -eq 0 ]; then
  echo "chrislusf/seaweedfs:$tag は約束を守っている"
else
  echo "chrislusf/seaweedfs:$tag: 赤 $failed 件"
fi
exit "$failed"
