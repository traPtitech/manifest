#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"/..

contains () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

rm -rf .built
mkdir .built

# ns-apps: No resource other than secret (which cannot be built in CI)
skip_dirs=("ns-apps")
for directory in $(echo ./*/ | tr -d './' | tr -d '/'); do
  if contains "$directory" "${skip_dirs[@]}"; then
    echo "Skipping ./$directory"
  else
    echo "Building ./$directory"
    kustomize build ./"$directory" --enable-alpha-plugins --enable-exec --load-restrictor LoadRestrictionsNone --enable-helm \
      | yq ".metadata.namespace = (.metadata.namespace // \"$directory\")" \
      > .built/"$directory".yaml
  fi
done
