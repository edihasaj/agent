#!/usr/bin/env bash
set -euo pipefail

mode="sync"
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "error: unknown argument: $1" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$HOME/.local/bin"
status=0

for helper in committer docs-list; do
  source_path="$repo_root/bin/$helper"
  target_path="$target_dir/$helper"

  if [[ -L "$target_path" && "$(readlink "$target_path")" == "$source_path" ]]; then
    echo "$helper: current"
    continue
  fi

  if [[ "$mode" == "check" ]]; then
    echo "error: $helper is not linked to $source_path" >&2
    status=1
    continue
  fi

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    echo "error: preserving user-owned file at $target_path; move it and rerun setup" >&2
    status=1
    continue
  fi

  mkdir -p "$target_dir"
  ln -sfn "$source_path" "$target_path"
  echo "$helper: linked $target_path -> $source_path"
done

exit "$status"
