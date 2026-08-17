#!/usr/bin/env bash
# Sync docs/slash-commands/*.md into runtime prompt dirs.
# Source of truth: docs/slash-commands/.
# Idempotent: re-run after adding/removing a command.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo/docs/slash-commands"

trash_or_remove() {
  if command -v trash >/dev/null 2>&1; then
    trash "$1"
  else
    rm -f "$1"
  fi
}

claude_targets=(
  "$HOME/.claude/commands"   # Claude Code global
  "$repo/.claude/commands"   # Claude Code project
)

codex_targets=(
  "$HOME/.codex/prompts"     # Codex global
  "$repo/.codex/prompts"     # Codex project mirror
)

for dir in "${claude_targets[@]}"; do
  mkdir -p "$dir"
  if [ -L "$dir/README.md" ] && [ "$(readlink "$dir/README.md")" = "$src/README.md" ]; then
    trash_or_remove "$dir/README.md"
  fi
  for f in "$src"/*.md; do
    name="$(basename "$f")"
    [ "$name" = "README.md" ] && continue
    ln -sfn "$f" "$dir/$name"
  done
  echo "synced -> $dir"
done

for dir in "${codex_targets[@]}"; do
  mkdir -p "$dir"
  if [ -e "$dir/README.md" ]; then
    trash_or_remove "$dir/README.md"
  fi
  for f in "$src"/*.md; do
    name="$(basename "$f")"
    [ "$name" = "README.md" ] && continue

    description="$(awk '
      /^---$/ { section++; next }
      section == 1 && /^description:/ { print; found=1; exit }
      section == 1 && /^summary:/ { fallback=$0 }
      END {
        if (!found && fallback) {
          sub(/^summary:/, "description:", fallback);
          print fallback;
        }
      }
    ' "$f")"

    argument_hint="$(awk '
      /^---$/ { section++; next }
      section == 1 && /^argument-hint:/ { print; exit }
    ' "$f")"

    tmp="$dir/.$name.tmp"
    {
      printf -- "---\n"
      printf "%s\n" "$description"
      if [ -n "$argument_hint" ]; then
        printf "%s\n" "$argument_hint"
      fi
      printf -- "---\n"
      awk '
        /^---$/ { section++; if (section == 2) { emit=1; next } }
        emit { print }
      ' "$f"
    } > "$tmp"
    mv "$tmp" "$dir/$name"
  done
  echo "synced -> $dir"
done
