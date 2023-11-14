#!/usr/bin/env bash

if [ "$#" -ne 3 ]; then
  echo "Usage:   $0 filename key data" >&2
  echo "Example: $0 ./argocd/secrets/notifications.yaml traq-webhook-id \"90a5ad8e-de6c-4900-931f-73bdeb571d12\"" >&2
  exit 1
fi

set -eux

sops --config .sops.yaml --set "[\"stringData\"][\"$2\"] \"$3\"" "$1"
