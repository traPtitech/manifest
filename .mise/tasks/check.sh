#!/usr/bin/env bash
#MISE description="kubeconform でマニフェストを検証"
#MISE dir="{{cwd}}"

set -eu

if [ "$#" -eq 0 ] && [ -t 0 ]; then
  set -- .
fi

exec kubeconform \
  -schema-location default \
  -schema-location "$MISE_PROJECT_ROOT/.crd/{{ .Group }}-{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json" \
  -skip apiextensions.k8s.io/v1/CustomResourceDefinition \
  "$@"
