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
source_path="$repo_root/scripts/committer"
target_dir="$HOME/.local/bin"
target_path="$target_dir/committer"

if [[ -L "$target_path" && "$(readlink "$target_path")" == "$source_path" ]]; then
  echo "committer: current"
  exit 0
fi

if [[ "$mode" == "check" ]]; then
  echo "error: committer is not linked to $source_path" >&2
  exit 1
fi

if [[ -e "$target_path" && ! -L "$target_path" ]]; then
  echo "error: preserving user-owned file at $target_path; move it and rerun setup" >&2
  exit 1
fi

mkdir -p "$target_dir"
ln -sfn "$source_path" "$target_path"
echo "committer: linked $target_path -> $source_path"
