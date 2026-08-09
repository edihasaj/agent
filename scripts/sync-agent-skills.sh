#!/usr/bin/env bash
set -euo pipefail

mode="sync"
include_private=1

usage() {
  cat <<'EOF'
usage: sync-agent-skills.sh [--check] [--public-only]

Link canonical public and private skills into the shared user registry and
Claude's compatibility registry. Existing non-symlink directories are kept.

Environment overrides:
  PRIVATE_SKILLS_ROOT  private source (default: ../manager/skills)
  AGENT_SKILLS_HOME    shared registry (default: ~/.agents/skills)
  CLAUDE_SKILLS_HOME   Claude registry (default: ~/.claude/skills)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check" ;;
    --public-only) include_private=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_root="$repo_root/skills"
private_root="${PRIVATE_SKILLS_ROOT:-$repo_root/../manager/skills}"
neutral_root="${AGENT_SKILLS_HOME:-$HOME/.agents/skills}"
claude_root="${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}"
legacy_codex_root="$HOME/.codex/skills"

source_roots=("$public_root")
if [[ "$include_private" -eq 1 && -d "$private_root" ]]; then
  private_root="$(cd "$private_root" && pwd)"
  source_roots+=("$private_root")
fi

skill_names=()
skill_dirs=()
public_count=0
private_count=0

for source_root in "${source_roots[@]}"; do
  for skill_dir in "$source_root"/*; do
    [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
    skill_name="${skill_dir##*/}"
    front_name="$(awk -F': *' '/^name:/{print $2; exit}' "$skill_dir/SKILL.md" | tr -d '"')"
    description="$(awk -F': *' '/^description:/{print $2; exit}' "$skill_dir/SKILL.md")"

    if [[ "$front_name" != "$skill_name" || -z "$description" ]]; then
      echo "error: invalid skill metadata: $skill_dir" >&2
      exit 1
    fi

    if [[ "${#skill_names[@]}" -gt 0 ]]; then
      for existing_name in "${skill_names[@]}"; do
        if [[ "$existing_name" == "$skill_name" ]]; then
          echo "error: duplicate skill name across sources: $skill_name" >&2
          exit 1
        fi
      done
    fi

    skill_names+=("$skill_name")
    skill_dirs+=("$skill_dir")
    if [[ "$source_root" == "$public_root" ]]; then
      public_count=$((public_count + 1))
    else
      private_count=$((private_count + 1))
    fi
  done
done

if [[ "$mode" == "sync" ]]; then
  mkdir -p "$neutral_root" "$claude_root"
fi

failures=0
for ((index = 0; index < ${#skill_names[@]}; index++)); do
  skill_name="${skill_names[$index]}"
  skill_dir="${skill_dirs[$index]}"

  for registry_root in "$neutral_root" "$claude_root"; do
    destination="$registry_root/$skill_name"
    if [[ "$mode" == "check" ]]; then
      if [[ ! -L "$destination" || "$(readlink "$destination")" != "$skill_dir" || ! -r "$destination/SKILL.md" ]]; then
        echo "mismatch: $destination -> $skill_dir" >&2
        failures=$((failures + 1))
      fi
    elif [[ -e "$destination" && ! -L "$destination" ]]; then
      echo "kept non-symlink: $destination" >&2
      failures=$((failures + 1))
    else
      ln -sfn "$skill_dir" "$destination"
    fi
  done

  legacy_link="$legacy_codex_root/$skill_name"
  if [[ -L "$legacy_link" ]]; then
    legacy_target="$(readlink "$legacy_link")"
    if [[ "$legacy_target" == "$public_root/"* ||
          "$legacy_target" == "$private_root/"* ||
          "$legacy_target" == *'/agent-scripts/skills/'* ]]; then
      if [[ "$mode" == "check" ]]; then
        echo "legacy Codex link: $legacy_link" >&2
        failures=$((failures + 1))
      else
        unlink "$legacy_link"
      fi
    fi
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "skill sync failed: $failures issue(s)" >&2
  exit 1
fi

echo "skills $mode complete: public=$public_count private=$private_count"
