#!/usr/bin/env sh

set -eux

echo "Installing commands for configured scripts ..."
apk add --no-cache git openssh curl npm

# Install kubectl
echo "Installing kubectl ..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

echo "Launching bot ..."
exec /work/dev-ops-bot "$@"
