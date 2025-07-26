#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"/..

if [ "$#" -ne 1 ]; then
  echo "現在の状態と指定のcommit/branchとのdiffをローカルで取る便利スクリプト（手元で実行することを想定）"
  echo "Usage: $0 [directory]"
  echo "Example: $0 traq"
  echo "Example: TARGET=feat/my-branch $0 traq"
  exit 1
fi

TARGET="${TARGET:-main}"

# Create a unique worktree directory in tmp
WORKTREE_DIR=$(mktemp -d /tmp/manifest.XXXXXX)

# Cleanup function to remove worktree on exit or failure
cleanup() {
  if [ -d "$WORKTREE_DIR" ]; then
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    rm -rf "$WORKTREE_DIR"
  fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo "==> Creating git worktree for ${TARGET} ..."
git worktree add -f "$WORKTREE_DIR" "${TARGET}"

echo "==> Building at ${TARGET} ..."
# Run build.sh in the worktree directory
(cd "$WORKTREE_DIR" && .scripts/build.sh "$@")
rm -rf .built.old
mv "$WORKTREE_DIR"/.built .built.old

echo "==> Building at current ..."
.scripts/build.sh "$@"

echo "==> Calculating diff ..."
.scripts/diff.sh .built.old .built --omit-header
