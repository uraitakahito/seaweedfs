#!/bin/sh
# 消費者の repo が、共有 store を 1 つの名前で呼んでいるかを見張る。
#
# store は crawler で 1 つ (`seaweedfs.crawler-storage`) だが、docs とコードには repo ごとの
# store を指した `seaweedfs.<project 名>` が残りうる。もう誰も立てていない名前なので**動かない**
# のに、宛先の綴りを確かめる試験は無いので試験では落ちない —— だから綴りのほうを検査する。
# 書き写した宛先は必ずずれる、というのが切り出す前からの教訓。
#
#   sh seaweedfs/scripts/check-store-name.sh crawler-storage
#
# 消費者の repo の根で走らせる。git が追っているテキストファイルだけを見る (submodule の
# 中身は gitlink なので自動的に外れる)。
#
# **一致は行ではなく 1 件ずつ見る。** 最初の版は `grep -v` で**行を**落としていたので、
# 共有の名前と古い名前が同じ行に並ぶと —— 「共有の名前に揃える。docs には repo ごとの名前が
# 残りうる」と**両方を挙げて説明する散文**はまさにこの形 —— その行ごと除外されて、古い綴りが
# 素通りした (browserhive の package.json の注釈で実際に素通りした。検査は緑のままだった)。
# `-o` で 1 件ずつ取り出してから比べる。
#
# なお、この検査は**説明の中の綴りも拾う**。古い名前を例として書きたいときは
# `seaweedfs.<project 名>` のように置き換える (`.` の後ろが英小文字でなければ拾わない)。
#
# 見つかれば一覧を出して 1 で終わる。
set -eu

shared="${1:?使い方: check-store-name.sh <共有 project 名>}"

# `seaweedfs.<name>` の形を全部拾い、共有の名前だけを許す。`seaweedfs.` の後ろに続くのは
# DNS のラベル (英小文字・数字・ハイフン)。
pattern='seaweedfs\.[a-z0-9][a-z0-9-]*'

# **ホスト名ではないもの。** `seaweedfs.` の後ろにはファイル名や repo の URL も来る ——
# `.gitmodules` の `uraitakahito/seaweedfs.git`、docs の `seaweedfs.md` など。拡張子で外す。
# `-o` の出力は `<行番号>:<一致した文字列>` なので、末尾まで一致させれば取り違えない。
not_host="^[0-9]+:seaweedfs\.(git|md|mdx|sh|ts|tsx|js|mjs|cjs|json|ya?ml|png|svg|txt|html|lock)$"

problems=0
for file in $(git ls-files); do
  [ -f "$file" ] || continue
  # -I で binary を飛ばす。見つからなければ grep は 1 を返すので、set -e の下では || true。
  bad_lines="$(grep -IonE "$pattern" "$file" 2>/dev/null \
    | grep -vE "^[0-9]+:seaweedfs\.${shared}$" \
    | grep -vE "$not_host" \
    | cut -d: -f1 | sort -un || true)"
  [ -z "$bad_lines" ] && continue
  problems=$((problems + 1))
  for n in $bad_lines; do
    echo "  $file:$n: $(sed -n "${n}p" "$file")"
  done
done

if [ "$problems" -gt 0 ]; then
  echo "" >&2
  echo "✗ 共有 store 以外の名前が残っている (${problems} ファイル)。" >&2
  echo "  宛先は seaweedfs.${shared} に揃える。store は crawler で 1 つしか立っていない。" >&2
  exit 1
fi

echo "✓ store の名前は seaweedfs.${shared} に揃っている"
