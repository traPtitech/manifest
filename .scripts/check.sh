#!/usr/bin/env bash

set -eu

cd "$(dirname "$0")"/..

exec kubeconform \
  -schema-location default \
  -schema-location '.crd/{{ .Group }}-{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json' \
  -skip apiextensions.k8s.io/v1/CustomResourceDefinition
