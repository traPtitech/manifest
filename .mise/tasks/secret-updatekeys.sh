#!/usr/bin/env bash
#MISE description="Secret の暗号化に使う鍵を更新"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename" >&2
  exit 1
fi

sops updatekeys "$1"
