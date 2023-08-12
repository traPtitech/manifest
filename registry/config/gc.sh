#!/bin/sh

while true; do
  sleep 86400
  echo "[gc.sh] Running garbage collection..."
  registry garbage-collect "$1" --delete-untagged
  echo "[gc.sh] Garbage collection complete."
done
