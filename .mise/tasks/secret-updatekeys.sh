#!/usr/bin/env bash
#MISE description="Secret の暗号化に使う鍵を更新"
#MISE dir="{{cwd}}"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename" >&2
  exit 1
fi

sops --config "$MISE_PROJECT_ROOT/.sops.yaml" updatekeys "$1"
