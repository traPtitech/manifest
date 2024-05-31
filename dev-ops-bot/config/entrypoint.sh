#!/usr/bin/env sh

set -eux

echo "Installing commands for configured scripts ..."
apk add --no-cache git openssh curl npm

# Install kubectl
echo "Installing kubectl ..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Set up kubectl context
# Use mounted service account token for connecting local cluster
# ref: https://www.ibm.com/docs/en/cloud-private/3.2.x?topic=kubectl-using-service-account-tokens-connect-api-server
echo "Configuring kubectl to use service account token ..."
kubectl config set-cluster cfc --server=https://kubernetes.default --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
kubectl config set-context cfc --cluster=cfc
kubectl config set-credentials user --token="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
kubectl config set-context cfc --user=user
kubectl config use-context cfc

echo "Launching bot ..."
exec /work/dev-ops-bot "$@"
