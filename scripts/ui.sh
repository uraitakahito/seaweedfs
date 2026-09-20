#!/bin/sh
# store を新しい順で見るための画面 (ui/index.html) を filer に置く。
#
#   sh scripts/ui.sh                        # 既定 http://127.0.0.1:8888
#   sh scripts/ui.sh http://127.0.0.1:8888  # 宛先を指す
#
# 普段は直に叩かない —— `stack.sh up` が最後に呼ぶので、画面を直したら
# `sh scripts/stack.sh up` で上書きされる。
#
# ## 置き先が /ui/ で、bucket の外なのはなぜか
#
#   - **bucket に置くと成果物の一覧に画面自身が出る。** 探しやすくするための
#     画面が、探すもののノイズになる。
#   - **wipe.sh で一緒に消える。** bucket を空にするのは開発中いちばん使う操作で、
#     そのたびに置き直すのは忘れる。
#   - filer が配るので画面と JSON が同一オリジンになり、CORS も Private Network
#     Access も関係しなくなる (docs サイト側に置く道はここで塞がる —— filer は
#     preflight に Access-Control-Allow-Private-Network を返さないので、https の
#     ページから 127.0.0.1 を叩くと Chrome が止める。実測)。
#
# 認証は要らない。filer の口は docker-compose.yml で 127.0.0.1 にだけ publish して
# あり、画面も同じ前提に乗っている。**公開しない。**
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
filer="${1:-http://127.0.0.1:8888}"
page="$root/ui/index.html"

[ -f "$page" ] || { echo "エラー: $page が無い。" >&2; exit 1; }

# up の直後は、コンテナが起きていても filer の口がまだ開いていない。**S3 の口
# (8333) と違って filer の / は 200 を返す**ので、ここは素直に -f で待てる
# (8333 は認証が要るので、立っていても 403。生死の判定に -f を使ってはいけない)。
waited=0
while [ "$waited" -lt 30 ]; do
  curl -fsS -o /dev/null "$filer/" 2>/dev/null && break
  waited=$((waited + 1))
  sleep 1
done

# **`|| true` を外さない。** `set -e` の下では、代入の中で curl が落ちると (繋がらない
# ときの 7 など) その場で script ごと終わる —— 下の case には一度も入らず、
# 名前を挙げた説明が出ないまま curl の終了コードだけが残る (実測で踏んだ)。
# 繋がらなかったときも curl は %{http_code} に 000 を書くので、判定は case に任せる。
code="$(curl -s -o /dev/null -w '%{http_code}' -F "file=@$page" "$filer/ui/index.html" || true)"
case "$code" in
  2*)
    echo "store の画面: $filer/ui/index.html"
    ;;
  *)
    echo "エラー: 画面を置けなかった (HTTP ${code}、${waited} 秒待った)。" >&2
    echo "filer は $filer で起きているか (sh scripts/stack.sh up)。" >&2
    exit 1
    ;;
esac
