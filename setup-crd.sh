#!/usr/bin/env bash

mkdir -p .crd
cd .crd || exit

# renovate:github-url
wget https://raw.githubusercontent.com/yannh/kubeconform/v0.7.0/scripts/openapi2jsonschema.py
export FILENAME_FORMAT='{fullgroup}-{kind}-{version}'

# renovate:github-url
python3 openapi2jsonschema.py https://raw.githubusercontent.com/argoproj/argo-cd/v3.0.2/manifests/install.yaml

# renovate:github-url
python3 openapi2jsonschema.py https://github.com/argoproj/argo-rollouts/releases/download/v1.8.2/install.yaml

# NOTE: In Argo Workflows, install.yaml contains only minimal CRDs; use full CRDs for validation:
# https://github.com/argoproj/argo-workflows/issues/11266
# renovate:github-url
kustomize build https://github.com/argoproj/argo-workflows//manifests/base/crds/full?ref=v3.6.7 > crd.yaml
python3 openapi2jsonschema.py crd.yaml && rm crd.yaml

# renovate:github-url
python3 openapi2jsonschema.py https://raw.githubusercontent.com/traefik/traefik/v3.4.0/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

# renovate:github-url
python3 openapi2jsonschema.py https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml

# renovate:github-url
python3 openapi2jsonschema.py https://github.com/rancher/system-upgrade-controller/releases/download/v0.15.2/crd.yaml
