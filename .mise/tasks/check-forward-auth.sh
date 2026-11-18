#!/usr/bin/env bash
#MISE description="forward auth を使うホストで /_oauth/ が middleware を通るかを検査"
#MISE dir="{{cwd}}"
#USAGE arg "<file>..." help="ビルド済みマニフェストのファイル（すべてのディレクトリ分をまとめて渡す）"

# forward auth（auth namespace の middleware）を付けたルートを持つホストごとに、
# 次のどちらかのルートがあることを確かめる。
# - ルールが Host(`<host>`) だけ（ホスト全体に middleware を付けている）
# - ルールに PathPrefix(`/_oauth/`) を含む
# ルールの評価や優先度は見ないので、README の「forward auth を使う場合」に書いた形で書く。
# https://github.com/traPtitech/traefik-forward-auth#routing-the-callback-path

set -euo pipefail

# 検査から外すホスト
# - q.trap.jp: widget が trapti.tech 用の middleware を使っていて、どの middleware を使うべきかが決まっていない
EXCLUDED_HOSTS=(q.trap.jp)

missing=$(yq eval-all --no-doc '
  [
    select(.kind == "IngressRoute") | .spec.routes[]
    | select([.middlewares[]? | select(.namespace == "auth")] | length > 0)
    | (.match | sub("\s+"; " ")) as $m
    | $m | match("Host[(]`([^`]*)`[)]"; "g") | .captures[0].string as $h
    | {"host": $h, "ok": ($m == "Host(`" + $h + "`)" or ($m | test("PathPrefix[(]`/_oauth/`[)]")))}
  ]
  | group_by(.host) | map(select(all_c(.ok == false))) | .[][0].host
' "$@" | grep -vxF -f <(printf '%s\n' "${EXCLUDED_HOSTS[@]}") || true)

if [ -n "$missing" ]; then
  echo >&2 "次のホストでは、/_oauth/ が forward auth の middleware を通りません。"
  echo >&2 "Host(\`<host>\`) && PathPrefix(\`/_oauth/\`) に、そのホストで使っている forward auth の middleware を付けたルートを足してください。"
  echo >&2 "https://github.com/traPtitech/traefik-forward-auth#routing-the-callback-path"
  echo >&2
  echo >&2 "$missing"
  exit 1
fi
