#!/bin/sh
# docs-site が指すものが、実物と食い違っていないかを見る。
#
# **`astro build` は守りにならない。** `.md` のページで何かが落ちても Starlight の
# docs loader が握り潰して exit 0 で終わる (`.mdx` だけが赤くなる)。この repo の
# ページは全部 `.md` なので、検査はこの script が全部である。
#
# 見るのは 3 つだけ。**対象が 0 件の検査は足さない** —— 永久に緑で、覆っているように
# 読めるだけになる (手本の capture-fixtures が BrowserHive 版から削ったのと同じ理由)。
#
#   1. en と ja が 1 対 1 で在るか (片方だけ足した・消した、を落とす)
#   2. 本文が名指しする repo の中のパスが実在するか
#   3. image の版の見本が docker-compose.yml と同じか (scripts/check-pin.sh)
#
# 1 を「見出しの一致」まで広げない。同じ見出しを強制すると日本語が悪くなる ——
# 対で在り続けることだけを機械が持ち、中身の歩調は人が合わせる。
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
docs="$root/docs-site/src/content/docs"
problems=0

note() {
  echo "  $1" >&2
  problems=$((problems + 1))
}

# ── 1. en と ja の対応。比べるのは **file 名**だけ。
for page in "$docs"/*.md; do
  [ -f "$page" ] || continue
  name="$(basename "$page")"
  [ -f "$docs/ja/$name" ] || note "ja/$name が無い (英語のページに日本語版が無い)"
done
for page in "$docs"/ja/*.md; do
  [ -f "$page" ] || continue
  name="$(basename "$page")"
  [ -f "$docs/$name" ] || note "$name が無い (日本語だけのページ。英語版が無い)"
done

# ── 2. 本文が backtick で名指しする repo の中のパス。
#
# 拾うのは `scripts/….sh` と `etc/….sh` と `docker-compose.yml` だけ ——
# 消えたときに黙って嘘になるのがこの 3 種で、他は散文の中の一般名詞と紛れる。
refs="$(grep -ohE '`(scripts/[a-z0-9.-]+\.sh|etc/[a-z0-9.-]+\.sh|docker-compose\.yml)`' \
  "$docs"/*.md "$docs"/ja/*.md 2>/dev/null | tr -d '`' | sort -u || true)"
for ref in $refs; do
  [ -e "$root/$ref" ] || note "docs が指す $ref が無い"
done

# ── 3. 版の見本。README ではなく **upgrading のページ**を見る (README は入口だけに畳んだ)。
for page in "$docs/upgrading.md" "$docs/ja/upgrading.md"; do
  if [ -f "$page" ]; then
    sh "$root/scripts/check-pin.sh" "$page" >/dev/null || note "$page の版の見本が docker-compose.yml とずれている"
  else
    note "$page が無い (版の見本を置く場所)"
  fi
done

if [ "$problems" -gt 0 ]; then
  echo "" >&2
  echo "✗ docs の参照が ${problems} 件ずれている。" >&2
  exit 1
fi

echo "✓ docs の参照は en/ja の対・repo のパス・版の見本とも揃っている"
