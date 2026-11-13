#!/usr/bin/env bash
#MISE description="マニフェストをビルド"
#MISE dir="{{cwd}}"

set -euo pipefail

if [ "$#" -eq 0 ]; then
  set -- .
fi

if [ "$#" -ne 1 ]; then
  echo >&2 "Build a kustomize directory."
  echo >&2 "Usage: $0 <dir-to-build>"
  echo >&2 "Example: $0 ./dev/karpenter"
  echo >&2 "Example: NAMESPACE=kube-system $0 ./dev/karpenter"
  exit 1
fi

BASENAME=$(basename "$(cd "$1" && pwd)")
NAMESPACE="${NAMESPACE:-$BASENAME}"

kustomize build "$1" --enable-alpha-plugins --enable-exec --load-restrictor LoadRestrictionsNone --enable-helm \
  | yq ".metadata.namespace = (.metadata.namespace // \"$NAMESPACE\")"
