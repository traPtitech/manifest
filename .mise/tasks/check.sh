#!/usr/bin/env bash
#MISE description="kubeconform でマニフェストを検証"

set -eu

cd "$(dirname "$0")"/../..

if [ "$#" -eq 0 ] && [ -t 0 ]; then
  set -- .
fi

exec kubeconform \
  -schema-location default \
  -schema-location '.crd/{{ .Group }}-{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json' \
  -skip apiextensions.k8s.io/v1/CustomResourceDefinition \
  "$@"
