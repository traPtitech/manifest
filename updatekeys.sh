#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename" >&2
  exit 1
fi

sops updatekeys "$1"
