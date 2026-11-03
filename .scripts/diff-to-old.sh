#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"/..

if [ "$#" -lt 1 ]; then
  echo >&2 "A utility script to build and compare a kustomize directory."
  echo >&2 "Usage: $0 <relative-dir-to-build> [dir2 [...]]"
  echo >&2 "Example: $0 ./dev/karpenter"
  echo >&2 "Example: TARGET=feat/my-branch $0 ./prod/*/"
  echo >&2 "Example: DYFF_OPTIONS=\"--omit-header --output github\" $0 ./prod/*/"
  exit 1
fi

TARGET="${TARGET:-main}"
DYFF_OPTIONS="${DYFF_OPTIONS:-"--omit-header"}"

# Create a unique worktree directory in tmp
WORKTREE_DIR=$(mktemp -d /tmp/manifest.XXXXXX)

# Temporary files for build output
BEFORE_TMP=$(mktemp)
AFTER_TMP=$(mktemp)

# Cleanup function to remove temporary files and directories on exit or failure
cleanup() {
  if [ -d "$WORKTREE_DIR" ]; then
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
    rm -rf "$WORKTREE_DIR"
  fi
  rm -f "$BEFORE_TMP"
  rm -f "$AFTER_TMP"
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo >&2 "==> Creating git worktree for ${TARGET} ..."
git worktree add -f "$WORKTREE_DIR" "${TARGET}" 1>&2

for dir in "$@"; do
  DIR="${dir%/}"

  echo >&2 "==> [$DIR] Building at current directory ..."
  .scripts/build.sh "$DIR" > "$AFTER_TMP"

  echo >&2 "==> [$DIR] Building at ${TARGET} ..."
  if [ -d "$WORKTREE_DIR/$DIR" ]; then
    BEFORE_DIR="$(cd "$WORKTREE_DIR/$DIR";pwd)"
    # Copy ./charts directory (if any) in current directory to avoid downloading twice
    if [ -d "$DIR/charts" ]; then
      cp -r "$DIR/charts" "$BEFORE_DIR/charts"
    fi
    .scripts/build.sh "$BEFORE_DIR" > "$BEFORE_TMP"
  else
    # If directory did not exist before, set empty result
    echo "" > "$BEFORE_TMP"
  fi

  echo >&2 "==> [$DIR] Calculating diff ..."
  .scripts/diff.sh "$BEFORE_TMP" "$AFTER_TMP" $DYFF_OPTIONS
done
