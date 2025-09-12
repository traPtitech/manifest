#!/usr/bin/env bash

if [ "$#" -ne 2 ]; then
  echo "既にsopsで暗号化されたSecretのキーを削除します。"
  echo "Usage:   $0 filename key" >&2
  echo "Example: $0 traq/secrets/env.yaml MY_ENV_NAME" >&2
  exit 1
fi

set -eux

sops --config .sops.yaml unset "$1" "[\"stringData\"][\"$2\"]"
