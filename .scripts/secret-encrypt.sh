#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename" >&2
  exit 1
fi

input_file="$1"
output_file="${input_file%.*}.enc.yaml"

sops --encrypt --config .sops.yaml --output "${output_file}" "${input_file}"
rm "${input_file}"