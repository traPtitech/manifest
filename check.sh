#!/usr/bin/env bash

set -euxo pipefail

contains () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# ns-apps: Skip because it contains secrets only (pipe fails with "no objects passed to apply")
skip_dirs=("ns-apps")
for directory in $(echo ./*/ | tr -d './' | tr -d '/'); do
  if ! contains "$directory" "${skip_dirs[@]}"; then
    kubectl create namespace "$directory" --dry-run=client -o yaml | kubectl apply -f -
  fi
done
for directory in $(echo ./*/ | tr -d './' | tr -d '/'); do
  if ! contains "$directory" "${skip_dirs[@]}"; then
    kustomize build ./"$directory" --enable-alpha-plugins --enable-exec --enable-helm | kubectl apply --validate=strict --dry-run=server -f -
  fi
done
