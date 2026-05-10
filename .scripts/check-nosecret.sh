#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--exclude-secrets|-e] <kustomize-dir>" >&2
}

include_secrets=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--exclude-secrets) include_secrets=false; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *) break ;;
  esac
done

dir="${1:-}"
if [ -z "$dir" ]; then usage; exit 2; fi

root="$(pwd)"
if [ ! -d "$dir" ]; then echo "Directory not found: $dir" >&2; exit 2; fi

_cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

# Require core tools up-front for clearer failures.
for cmd in kustomize yq; do
  if ! _cmd_exists "$cmd"; then echo "Error: $cmd not found in PATH" >&2; exit 3; fi
done

# yq (mikefarah/yq v4) の呼び出し差異を吸収
YQ_CMD="yq"
if yq eval --version >/dev/null 2>&1; then YQ_CMD="yq eval"; fi

# Work in an isolated copy to avoid touching the working tree.
tmpd=$(mktemp -d)
trap 'rm -rf "$tmpd"' EXIT

tmp_repo="$tmpd/repo"
echo "[validate] Copying repository to temporary directory..." >&2

if _cmd_exists rsync; then
  rsync -a --exclude='.git' --exclude='mise.toml' "$root/" "$tmp_repo/"
else
  cp -a "$root/." "$tmp_repo/"
fi
target_dir="$tmp_repo/$dir"

echo "[validate] Scrubbing encrypted secret values..." >&2
# Remove data/stringData content from encrypted Secret manifests.
find "$tmp_repo" -type f -name '*.enc.yaml' -print0 | while IFS= read -r -d '' enc_file; do
  $YQ_CMD -i '
    select(.kind == "Secret") |= (
      del(.sops) |
      (select(has("data")).data[]) = "" |
      (select(has("stringData")).stringData[]) = ""
    )
  ' "$enc_file"
done

echo "[validate] Bypassing ksops generators..." >&2
# Replace ksops generators with direct file resources (optionally).
find "$tmp_repo" -type f \( -name 'kustomization.yaml' -o -name 'kustomization.yml' -o -name 'kustomize.yaml' \) -print0 | while IFS= read -r -d '' k_file; do
  base_dir=$(dirname "$k_file")
  
  for field in "generators" "components" "resources"; do
    items=$($YQ_CMD ".$field[]" "$k_file" 2>/dev/null || true)
    [ -z "$items" ] || [ "$items" = "null" ] && continue
    
    modified=false
    added_resources=false
    
    while IFS= read -r item; do
      [ -z "$item" ] || [ "$item" = "null" ] && continue
      
      item_path="$base_dir/$item"
      if [ -f "$item_path" ] && [ "$($YQ_CMD '.kind' "$item_path" 2>/dev/null || true)" = "ksops" ]; then
        modified=true
        
        # ksopsジェネレータの記述を削除
        $YQ_CMD -i "del(.$field[] | select(. == \"$item\"))" "$k_file"
        
        # include_secrets=trueの場合、暗号化ファイル本体を resources として直接追加
        if [ "$include_secrets" = true ]; then
          files=$($YQ_CMD '.files[]' "$item_path" 2>/dev/null || true)
          item_dir=$(dirname "$item")
          
          while IFS= read -r f; do
            [ -z "$f" ] || [ "$f" = "null" ] && continue
            [ "$item_dir" != "." ] && f="$item_dir/$f"
            $YQ_CMD -i ".resources += [\"$f\"]" "$k_file"
            added_resources=true
          done <<< "$files"
        fi
      fi
    done <<< "$items"
    
    # 変更があった場合のクリーンアップ
    if [ "$modified" = true ]; then
      if [ "$added_resources" = true ]; then
        $YQ_CMD -i '.resources |= unique' "$k_file" 2>/dev/null || true
      fi
      $YQ_CMD -i "del(.$field | select(. == []))" "$k_file" 2>/dev/null || true
    fi
  done
done

out_yaml="$tmpd/kustomize-output.yaml"
echo "[validate] Running kustomize build..." >&2

(
  cd "$target_dir"
  if ! kustomize build . \
    --enable-alpha-plugins \
    --enable-exec \
    --load-restrictor LoadRestrictionsNone \
    --enable-helm > "$out_yaml" 2> "$tmpd/kerror.log"; then
    echo "kustomize build failed:" >&2
    cat "$tmpd/kerror.log" >&2
    exit 4
  fi
)

if _cmd_exists kubeconform; then
  echo "[validate] Running kubeconform validation..." >&2
  if ! kubeconform \
    -summary \
    -strict \
    -exit-on-error \
    -schema-location default \
    -schema-location "$root/.crd/{{ .Group }}-{{ .ResourceKind }}-{{ .ResourceAPIVersion }}.json" \
    -skip apiextensions.k8s.io/v1/CustomResourceDefinition \
    -ignore-missing-schemas \
    "$out_yaml" >&2; then
    echo "kubeconform: validation failed" >&2
    exit 5
  fi
elif _cmd_exists kubectl; then
  echo "[validate] Running kubectl client-side dry-run validation..." >&2
  if ! kubectl apply --dry-run=client -f "$out_yaml" >/dev/null 2>&1; then
    echo "kubectl dry-run: validation failed" >&2
    exit 6
  fi
fi

# Emit the final, scrubbed manifest to stdout.
cat "$out_yaml"