#!/bin/sh
# 消費者の repo が、共有 store を 1 つの名前で呼んでいるかを見張る。
#
# store は 1 つに寄せたのに、docs とコードには `seaweedfs.<自分の project 名>` が残りうる。
# 残った綴りは**動く**かもしれない (自分の store を立てていれば) ので、試験では落ちない ——
# だから綴りのほうを検査する。書き写した宛先は必ずずれる、というのが切り出す前からの教訓。
#
#   sh seaweedfs/scripts/check-store-name.sh crawler-storage [除外するパス...]
#
# 消費者の repo の根で走らせる。git が追っているテキストファイルだけを見る (submodule の
# 中身は gitlink なので自動的に外れる)。
#
# **除外は「自前の store を指すのが正しい場所」だけ。** browserhive の e2e は使い捨ての
# store を自分の project に立てるので、そこに `seaweedfs.browserhive` が在るのは正しい。
# 除外を増やすときは、その場所が本当に「自前の store の話」かを確かめること。
#
# 見つかれば一覧を出して 1 で終わる。
set -eu

shared="${1:?使い方: check-store-name.sh <共有 project 名> [除外するパス...]}"
shift

# `seaweedfs.<name>` の形を全部拾い、共有の名前だけを許す。`seaweedfs.` の後ろに続くのは
# DNS のラベル (英小文字・数字・ハイフン)。
pattern='seaweedfs\.[a-z0-9][a-z0-9-]*'

# **ホスト名ではないもの。** `seaweedfs.` の後ろにはファイル名や repo の URL も来る ——
# `.gitmodules` の `uraitakahito/seaweedfs.git`、docs の `seaweedfs.md` など。拡張子で外す。
# (同じ行にホスト名とファイル名が両方あると、その行ごと見逃す。稀なので、そこは許す。)
not_host='seaweedfs\.(git|md|mdx|sh|ts|tsx|js|mjs|cjs|json|ya?ml|png|svg|txt|html|lock)([^a-z0-9-]|$)'

excluded() {
  for path in "$@"; do
    [ "$path" = "$candidate" ] && return 0
  done
  return 1
}

problems=0
for file in $(git ls-files); do
  [ -f "$file" ] || continue
  candidate="$file"
  excluded "$@" && continue
  # -I で binary を飛ばす。見つからなければ grep は 1 を返すので、set -e の下では || true。
  hits="$(grep -InE "$pattern" "$file" 2>/dev/null \
    | grep -vE "seaweedfs\.${shared}([^a-z0-9-]|$)" \
    | grep -vE "$not_host" || true)"
  [ -z "$hits" ] && continue
  echo "$hits" | while IFS= read -r line; do
    echo "  $file:$line"
  done
  problems=$((problems + 1))
done

if [ "$problems" -gt 0 ]; then
  echo "" >&2
  echo "✗ 共有 store 以外の名前が残っている (${problems} ファイル)。" >&2
  echo "  宛先は seaweedfs.${shared} に揃える。自前の store を指すのが正しい場所は、" >&2
  echo "  この検査の引数に足す (seaweedfs/scripts/check-store-name.sh の冒頭を読むこと)。" >&2
  exit 1
fi

echo "✓ store の名前は seaweedfs.${shared} に揃っている"
