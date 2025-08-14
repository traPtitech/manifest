#!/usr/bin/env bash

set -euo pipefail

TARGET=""
if [ "$#" -ge 1 ]; then
  TARGET=$1
fi

contains () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

rm -rf .built
mkdir .built

skip_dirs=()
for directory in $(echo ./*/ | tr -d './' | tr -d '/'); do
  if contains "$directory" "${skip_dirs[@]}"; then
    echo "Skipping $directory"
    continue
  fi
  if [ -n "$TARGET" ] && [ "$TARGET" != "$directory" ]; then
    continue
  fi

  echo "Building ./$directory"
  kustomize build ./"$directory" --enable-alpha-plugins --enable-exec --load-restrictor LoadRestrictionsNone --enable-helm \
    | yq ".metadata.namespace = (.metadata.namespace // \"$directory\")" \
    > .built/"$directory".yaml
done
