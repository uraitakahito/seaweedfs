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
#   sh scripts/stack.sh up            # 起動 (-d -b は既定で付く)
#   sh scripts/stack.sh down          # 停止
#
# 余分な引数はそのまま container-compose へ渡る。down には点検を掛けない ——
# DNS ドメインが無くても、止めることはできるべきだから。
set -eu

cd "$(dirname "$0")/.."

SUBCOMMAND="${1:-up}"
shift || true

DOMAIN=crawler-storage

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

case "${SUBCOMMAND}" in
  up)
    preflight
    echo "共有 store を起こす (bucket は docker-compose.yml の S3_BUCKETS)"
    # **exec で置き換えない。** 置き換えると、この下は 1 行も走らない。
    container-compose up -d -b "$@"
    # 中身を新しい順で見る画面を置き直す (filer の /ui/index.html)。起こすたびに
    # 上書きするので、画面を直したら up し直せばそれで反映される。
    #
    # 失敗しても up は成功のまま終える —— store は画面が無くても本来の仕事をする。
    # ここで落とすと「見るための飾りが無い」だけで store が使えなくなる。
    sh scripts/ui.sh || echo "（画面は置けなかった。store は使える）" >&2
    ;;
  down)
    exec container-compose down "$@"
    ;;
  *)
    echo "使い方: $0 [up|down] [container-compose への追加の引数...]" >&2
    exit 2
    ;;
esac
