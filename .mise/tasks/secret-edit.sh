#!/usr/bin/env bash
#MISE description="Secret を復号してエディターで編集"
#MISE dir="{{cwd}}"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename" >&2
  exit 1
fi

EDITOR=${EDITOR:-nano} sops --config "$MISE_PROJECT_ROOT/.sops.yaml" --in-place "$1"
