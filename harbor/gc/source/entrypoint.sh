#!/usr/bin/env bash

set -euxo pipefail

curl https://rclone.org/install.sh | bash

go run . -read-object-prefix trap-wasabi-registry:/trap-ns-registry/
