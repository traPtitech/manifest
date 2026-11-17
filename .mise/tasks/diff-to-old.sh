#!/usr/bin/env bash
#MISE description="マニフェストの差分を古い状態と比較して表示"
#MISE dir="{{cwd}}"

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo >&2 "A utility script to build and compare a kustomize directory."
  echo >&2 "Usage: $0 <relative-dir-to-build> [dir2 [...]]"
  echo >&2 "Example: $0 ./dev/karpenter"
  echo >&2 "Example: TARGET=feat/my-branch $0 ./prod/*/"
  echo >&2 "Example: DYFF_OPTIONS=\"--omit-header --output human\" $0 ./prod/*/"
  exit 1
fi

PROJECT_ROOT=$(cd "$MISE_PROJECT_ROOT" && pwd -P)
TARGET="${TARGET:-main}"
DYFF_OPTIONS="${DYFF_OPTIONS:---omit-header --output human}"

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
  CURRENT_DIR=$(cd "$dir" && pwd -P)
  case "$CURRENT_DIR/" in
    "$PROJECT_ROOT/"*) DIR=${CURRENT_DIR#"$PROJECT_ROOT"/} ;;
    *) echo >&2 "Directory is outside the project: $dir"; exit 1 ;;
  esac
  if [ "$CURRENT_DIR" = "$PROJECT_ROOT" ]; then
    DIR=.
  fi

  echo >&2 "==> [$DIR] Building at current directory ..."
  mise run build "$CURRENT_DIR" > "$AFTER_TMP"

  echo >&2 "==> [$DIR] Building at ${TARGET} ..."
  if [ -d "$WORKTREE_DIR/$DIR" ]; then
    BEFORE_DIR="$(cd "$WORKTREE_DIR/$DIR";pwd)"
    # Copy ./charts directory (if any) in current directory to avoid downloading twice
    if [ -d "$CURRENT_DIR/charts" ]; then
      cp -r "$CURRENT_DIR/charts" "$BEFORE_DIR/charts"
    fi
    mise run build "$BEFORE_DIR" > "$BEFORE_TMP"
  else
    # If directory did not exist before, set empty result
    echo "" > "$BEFORE_TMP"
  fi

  echo >&2 "==> [$DIR] Calculating diff ..."
  mise run diff "$BEFORE_TMP" "$AFTER_TMP" $DYFF_OPTIONS
done
