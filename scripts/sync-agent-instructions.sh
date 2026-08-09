#!/usr/bin/env bash
set -euo pipefail

mode="sync"
selected_clis=()

usage() {
  cat <<'EOF'
usage: sync-agent-instructions.sh [--check] [--cli NAME]...

Link the canonical AGENTS.MD into each supported CLI's user-level instruction
path. Existing regular files are preserved and receive the canonical pointer
as their first line.

Options:
  --check       report drift without changing files
  --cli NAME    configure home, codex, claude, opencode, gemini, or copilot;
                repeat to configure multiple CLIs

Environment overrides:
  AGENT_INSTRUCTIONS_SOURCE   canonical file (default: ../AGENTS.MD)
  AGENT_INSTRUCTIONS_POINTER  path written into preserved files
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check" ;;
    --cli)
      [[ $# -ge 2 ]] || { echo "error: --cli requires a value" >&2; exit 2; }
      selected_clis+=("$2")
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
canonical_source="${AGENT_INSTRUCTIONS_SOURCE:-$repo_root/AGENTS.MD}"
pointer_path="${AGENT_INSTRUCTIONS_POINTER:-~/Projects/agent/AGENTS.MD}"
pointer_line="READ $pointer_path BEFORE ANYTHING (skip if missing)."

if [[ ! -f "$canonical_source" ]]; then
  echo "error: canonical instructions not found: $canonical_source" >&2
  exit 1
fi
canonical_source="$(cd "$(dirname "$canonical_source")" && pwd)/$(basename "$canonical_source")"

if [[ "${#selected_clis[@]}" -eq 0 ]]; then
  selected_clis=(home codex claude opencode gemini copilot)
fi

targets=()
cli_names=()
for cli_name in "${selected_clis[@]}"; do
  case "$cli_name" in
    home) destination="$HOME/AGENTS.md" ;;
    codex) destination="$HOME/.codex/AGENTS.md" ;;
    claude) destination="$HOME/.claude/CLAUDE.md" ;;
    opencode) destination="$HOME/.config/opencode/AGENTS.md" ;;
    gemini) destination="$HOME/.gemini/GEMINI.md" ;;
    copilot) destination="$HOME/.github/copilot-instructions.md" ;;
    *) echo "error: unknown CLI: $cli_name" >&2; exit 2 ;;
  esac

  already_selected=0
  if [[ "${#cli_names[@]}" -gt 0 ]]; then
    for existing_cli in "${cli_names[@]}"; do
      [[ "$existing_cli" == "$cli_name" ]] && already_selected=1
    done
  fi
  [[ "$already_selected" -eq 1 ]] && continue
  cli_names+=("$cli_name")
  targets+=("$destination")
done

failures=0
linked=0
preserved=0

for destination in "${targets[@]}"; do
  if [[ -L "$destination" ]]; then
    if [[ "$(readlink "$destination")" == "$canonical_source" && -r "$destination" ]]; then
      linked=$((linked + 1))
      continue
    fi

    if [[ "$mode" == "check" ]]; then
      echo "mismatch: $destination -> $canonical_source" >&2
      failures=$((failures + 1))
    else
      ln -sfn "$canonical_source" "$destination"
      linked=$((linked + 1))
    fi
    continue
  fi

  if [[ -e "$destination" && ! -f "$destination" ]]; then
    echo "error: instruction target is not a file: $destination" >&2
    failures=$((failures + 1))
    continue
  fi

  if [[ -f "$destination" ]]; then
    if [[ "$(sed -n '1p' "$destination")" == "$pointer_line" ]]; then
      preserved=$((preserved + 1))
      continue
    fi

    if [[ "$mode" == "check" ]]; then
      echo "missing pointer: $destination" >&2
      failures=$((failures + 1))
      continue
    fi

    temporary="$(mktemp "${destination}.tmp.XXXXXX")"
    {
      printf '%s\n\n' "$pointer_line"
      awk -v pointer="$pointer_line" '$0 != pointer { print }' "$destination"
    } > "$temporary"
    if file_mode="$(stat -f '%Lp' "$destination" 2>/dev/null)"; then
      chmod "$file_mode" "$temporary"
    else
      chmod "$(stat -c '%a' "$destination")" "$temporary"
    fi
    mv "$temporary" "$destination"
    preserved=$((preserved + 1))
    continue
  fi

  if [[ "$mode" == "check" ]]; then
    echo "missing: $destination" >&2
    failures=$((failures + 1))
  else
    mkdir -p "$(dirname "$destination")"
    ln -s "$canonical_source" "$destination"
    linked=$((linked + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "instruction sync failed: $failures issue(s)" >&2
  exit 1
fi

cli_list="$(IFS=,; echo "${cli_names[*]}")"
echo "instructions $mode complete: linked=$linked preserved=$preserved clis=$cli_list"
