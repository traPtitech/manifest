#!/usr/bin/env bash

set -euxo pipefail

apt update
apt install -y zip
curl https://rclone.org/install.sh | bash

go run . -read-object-prefix trap-wasabi-registry:/trap-ns-registry/ -doit
