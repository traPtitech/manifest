#!/usr/bin/env bash
set -euo pipefail

archive=$(mktemp)
trap 'rm -f "$archive" ksops-dry-run' EXIT
curl -fsSL https://github.com/motoki317/ksops-dry-run/releases/download/v0.3.1/ksops-dry-run-linux-amd64.tar.gz -o "$archive"
tar -xzf "$archive" ksops-dry-run
sudo install ksops-dry-run /usr/local/bin/ksops
