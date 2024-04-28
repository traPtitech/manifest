#!/usr/bin/env sh

echo "Installing commands for configured scripts ..."
apk add --no-cache git openssh curl npm

echo "Launching bot ..."
exec /work/dev-ops-bot "$@"
