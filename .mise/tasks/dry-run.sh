#!/usr/bin/env bash
#MISE description="Secret の値をプレースホルダーに置き換えてタスクを実行"

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: mise run dry-run <task> [args...]" >&2
  exit 1
fi

plugin_dir=$(mktemp -d)
trap 'rm -rf "$plugin_dir"' EXIT
ln -s "$MISE_PROJECT_ROOT/.mise/scripts/ksops" "$plugin_dir/ksops"
export PATH="$plugin_dir:$PATH"
export MISE_DISABLE_TOOLS="${MISE_DISABLE_TOOLS:+$MISE_DISABLE_TOOLS,}ksops"
mise run "$@"
