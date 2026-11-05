#!/bin/sh
# 共有 store の起動と停止。**これが唯一の起動方法。**
#
# ## なぜ包むのか
#
# 起こす前に確かめたい前提が 2 つあり、どちらも黙って壊れる:
#
#   - 道具: container / container-compose が PATH に在るか。container が無いまま DNS の
#     検査に進むと、「DNS ドメインが無い」と取り違えて報告してしまう。
#   - DNS ドメイン: compose の project 名 (crawler-storage) と同じ名前のドメインが
#     登録されていること。無いと container-compose は、起動後に `container exec` で
#     **各コンテナの中の** /etc/hosts へ相手の行を追記する方式に落ちる。この store は
#     1 コンテナなので自分は困らないが、**消費者から seaweedfs.crawler-storage が引けなくなる**
#     —— つまり「立っているのに誰も届かない」という、いちばん読みにくい形になる。
#
#   sh scripts/stack.sh up            # 起動 (-d -b は既定で付く)。S3 の口が答えるまで返らない
#   sh scripts/stack.sh down          # 停止
#
# 余分な引数はそのまま container-compose へ渡る。down には点検を掛けない ——
# DNS ドメインが無くても、止めることはできるべきだから。
set -eu

cd "$(dirname "$0")/.."

SUBCOMMAND="${1:-up}"
shift || true

DOMAIN=crawler-storage
S3_URL=http://127.0.0.1:8333/
S3_WAIT_SECONDS=60

preflight() {
  for cmd in container container-compose; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "エラー: \`${cmd}\` が PATH に見つかりません。" >&2
      echo "Apple Container と container-compose を (Homebrew で) 入れてから、もう一度起動してください。" >&2
      exit 1
    fi
  done

  # 一覧を変数に取ってから探す。`set -o pipefail` を持つ shell で `container … | grep -q` と
  # 繋ぐと、grep が先に終わったときの SIGPIPE で左側が 141 を返し、「在るのに無い」と
  # 判定しうる。
  domains="$(container system dns ls 2>/dev/null || true)"
  if ! echo "${domains}" | grep -qx "${DOMAIN}"; then
    echo "エラー: DNS ドメイン '${DOMAIN}' が登録されていません。" >&2
    echo "" >&2
    echo "    sudo container system dns create ${DOMAIN}" >&2
    echo "" >&2
    echo "上のコマンドを一度だけ実行してから (sudo が要ります)、もう一度起動してください。" >&2
    echo "これが無いと store は立ちますが、消費者から seaweedfs.${DOMAIN} を引けません。" >&2
    exit 1
  fi
}

# **起こした直後、S3 の口はまだ開いていない** (master の起動から約 12 秒。実測)。消費者は up が
# 返った直後に使う —— capture-ledger の dev:up は、すぐ後の段で 8333 を確かめ、開いていなければ
# 落ちる。だから up は、S3 が答えるまで返らない。
#
# 答えは状態の数字で見る。S3 は匿名に 403 を返すので、`curl -f` では立っていても失敗に見える。
# **`|| true` を外さない。** 繋がらないときの curl の失敗で、`set -e` が script ごと終わらせる
# (繋がらなければ curl は %{http_code} に 000 を書くので、判定は case に任せる)。
wait_for_s3() {
  deadline=$(($(date +%s) + S3_WAIT_SECONDS))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "${S3_URL}" || true)"
    case "${code}" in
      [1-5]??) return 0 ;;
    esac
    sleep 1
  done
  echo "エラー: S3 の口 (${S3_URL}) が ${S3_WAIT_SECONDS} 秒待っても開きません。" >&2
  echo "container logs seaweedfs.${DOMAIN} を見てください。" >&2
  exit 1
}

case "${SUBCOMMAND}" in
  up)
    preflight
    echo "共有 store を起こす (bucket は docker-compose.yml の S3_BUCKETS)"
    # **exec で置き換えない。** 置き換えると、この下は 1 行も走らない。
    container-compose up -d -b "$@"
    wait_for_s3
    ;;
  down)
    exec container-compose down "$@"
    ;;
  *)
    echo "使い方: $0 [up|down] [container-compose への追加の引数...]" >&2
    exit 2
    ;;
esac
