#!/usr/bin/env bash
set -euo pipefail

mode="sync"
include_private=1
selected_registries=()

usage() {
  cat <<'EOF'
usage: sync-agent-skills.sh [--check] [--public-only] [--registry NAME]...

Link canonical public and private skills into every agent runtime registry,
and slash commands into Claude and each Codex profile. Existing non-symlink
directories are kept.

Options:
  --check            report drift without changing files
  --public-only      ignore the sibling private manager repo
  --registry NAME    shared | claude | codex | cursor; repeat to select several
                     (codex expands to every discovered profile)

Environment overrides:
  PRIVATE_SKILLS_ROOT   private source (default: ../manager/skills)
  AGENT_SKILLS_HOME     shared registry (default: ~/.agents/skills)
  CLAUDE_SKILLS_HOME    Claude registry (default: ~/.claude/skills)
  CURSOR_SKILLS_HOME    Cursor registry (default: ~/.cursor/skills)
  CLAUDE_COMMANDS_HOME  Claude commands (default: ~/.claude/commands)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check" ;;
    --public-only) include_private=0 ;;
    --registry)
      [[ $# -ge 2 ]] || { echo "error: --registry requires a value" >&2; exit 2; }
      selected_registries+=("$2")
      shift
      ;;
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
cursor_root="${CURSOR_SKILLS_HOME:-$HOME/.cursor/skills}"

# Codex discovers skills only from "$CODEX_HOME/skills" and prompts only from
# "$CODEX_HOME/prompts"; it does not read the neutral registry. Each profile is
# a separate CODEX_HOME (~/.codex, ~/.codex-primary, ~/.codex-secondary, ...),
# so populate every one.
codex_homes=()
for codex_candidate in "$HOME"/.codex "$HOME"/.codex-*; do
  [[ -d "$codex_candidate" && -f "$codex_candidate/config.toml" ]] || continue
  codex_homes+=("$codex_candidate")
done

# TODO: adding another runtime or profile
#   - Codex profile: nothing to do; any ~/.codex-<name> with a config.toml is
#     discovered automatically by the loop above.
#   - New runtime with its own registry: add a *_root variable above, a case
#     branch below, and its name to the default list. If it reads commands or
#     prompts too, add it to command_targets further down.
#   - A runtime that reads the neutral ~/.agents/skills needs no entry.

if [[ "${#selected_registries[@]}" -eq 0 ]]; then
  selected_registries=(shared claude codex cursor)
fi

registry_roots=()
registry_names=()
use_shared=0
for registry_name in "${selected_registries[@]}"; do
  resolved_names=()
  resolved_roots=()
  case "$registry_name" in
    shared) resolved_names=(shared); resolved_roots=("$neutral_root"); use_shared=1 ;;
    claude) resolved_names=(claude); resolved_roots=("$claude_root") ;;
    cursor) resolved_names=(cursor); resolved_roots=("$cursor_root") ;;
    codex)
      for codex_home in ${codex_homes+"${codex_homes[@]}"}; do
        resolved_names+=("codex:${codex_home##*/}")
        resolved_roots+=("$codex_home/skills")
      done
      ;;
    *) echo "error: unknown registry: $registry_name" >&2; exit 2 ;;
  esac

  for ((resolved_index = 0; resolved_index < ${#resolved_names[@]}; resolved_index++)); do
    candidate_name="${resolved_names[$resolved_index]}"
    already_selected=0
    if [[ "${#registry_names[@]}" -gt 0 ]]; then
      for existing_registry in "${registry_names[@]}"; do
        [[ "$existing_registry" == "$candidate_name" ]] && already_selected=1
      done
    fi
    [[ "$already_selected" -eq 1 ]] && continue
    registry_names+=("$candidate_name")
    registry_roots+=("${resolved_roots[$resolved_index]}")
  done
done

# docs/slash-commands is the tracked source of truth for slash commands.
command_roots=()
[[ -d "$repo_root/docs/slash-commands" ]] && command_roots+=("$repo_root/docs/slash-commands")
if [[ "$include_private" -eq 1 && -d "$private_root/../commands" ]]; then
  command_roots+=("$(cd "$private_root/../commands" && pwd)")
fi

# Claude reads ~/.claude/commands; each Codex profile reads its own prompts dir.
command_targets=("${CLAUDE_COMMANDS_HOME:-$HOME/.claude/commands}")
for codex_home in ${codex_homes+"${codex_homes[@]}"}; do
  command_targets+=("$codex_home/prompts")
done

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
  mkdir -p "${registry_roots[@]}"
fi

failures=0
for ((index = 0; index < ${#skill_names[@]}; index++)); do
  skill_name="${skill_names[$index]}"
  skill_dir="${skill_dirs[$index]}"

  for registry_root in "${registry_roots[@]}"; do
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

done

command_count=0
if [[ "${#command_roots[@]}" -gt 0 ]]; then
  [[ "$mode" == "sync" ]] && mkdir -p "${command_targets[@]}"
  for command_root in "${command_roots[@]}"; do
    for command_file in "$command_root"/*.md; do
      [[ -f "$command_file" ]] || continue
      command_name="${command_file##*/}"
      [[ "$command_name" == "README.md" ]] && continue
      command_count=$((command_count + 1))
      for command_target in "${command_targets[@]}"; do
        destination="$command_target/$command_name"
        if [[ "$mode" == "check" ]]; then
          if [[ ! -L "$destination" || "$(readlink "$destination")" != "$command_file" ]]; then
            echo "command mismatch: $destination -> $command_file" >&2
            failures=$((failures + 1))
          fi
        elif [[ -e "$destination" && ! -L "$destination" ]]; then
          echo "kept non-symlink command: $destination" >&2
          failures=$((failures + 1))
        else
          ln -sfn "$command_file" "$destination"
        fi
      done
    done
  done
fi

if [[ "$failures" -ne 0 ]]; then
  echo "skill sync failed: $failures issue(s)" >&2
  exit 1
fi

registry_list="$(IFS=,; echo "${registry_names[*]}")"
echo "skills $mode complete: public=$public_count private=$private_count commands=$command_count registries=$registry_list"
