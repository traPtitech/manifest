#!/usr/bin/env bash

exec kubeconform \
  -schema-location default \
  -schema-location '.crd/{{ .Group }}-{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json' \
  -skip apiextensions.k8s.io/v1/CustomResourceDefinition
