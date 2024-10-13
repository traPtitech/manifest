#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <before dir> <after dir> [extra dyff options]"
  exit 1
fi

convert() {
  if [ "$#" -ne 2 ]; then
    echo "Invalid internal function usage"
    exit 1
  fi

  BASE_DIR=$1
  OUTPUT=$2

  # Exclude some diffs when templating locally
  yq '.' "$BASE_DIR"/*.yaml \
    | yq '(select(.metadata.namespace == "harbor" and .kind == "Secret") | .data) = {}' \
    | yq '(select(.metadata.namespace == "harbor" and .kind == "Deployment") | .spec.template.metadata.annotations.checksum/secret) = ""' \
    | yq '(select(.metadata.namespace == "harbor" and .kind == "Deployment") | .spec.template.metadata.annotations.checksum/secret-core) = ""' \
    | yq '(select(.metadata.namespace == "harbor" and .kind == "Deployment") | .spec.template.metadata.annotations.checksum/secret-jobservice) = ""' \
    > "$OUTPUT"
}

BEFORE=$1
AFTER=$2
OPTIONS=( "${@:3}" )

trap 'rm -f before.yaml after.yaml' EXIT
convert "$BEFORE" before.yaml
convert "$AFTER" after.yaml

# https://stackoverflow.com/questions/7577052/unbound-variable-error-in-bash-when-expanding-empty-array
dyff between before.yaml after.yaml ${OPTIONS[@]+"${OPTIONS[@]}"}
