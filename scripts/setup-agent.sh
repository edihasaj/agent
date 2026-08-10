#!/usr/bin/env bash
set -euo pipefail

mode="sync"
include_private=1
all_clis=0
headless=0
expected_platform=""
requested_clis=()
supported_clis=(codex claude opencode gemini copilot)

# Non-login SSH and service shells commonly omit user-installed CLI locations.
# Add only executable locations; never source profiles or secrets during setup.
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

usage() {
  cat <<'EOF'
usage: setup-agent.sh [--check] [--public-only] [--headless] [--all-clis] [--cli NAME]...

Configure shared instructions, skills, and MCPs for the CLIs found on PATH.
By default, only detected CLIs are configured. Re-running is safe.

Options:
  --check          report drift without changing files
  --public-only    skip private skills from the sibling manager repo
  --headless       remove browser/GUI MCPs that need a local desktop
  --all-clis       configure every supported CLI, installed or not
  --cli NAME       configure one CLI explicitly; repeat for multiple CLIs
  -h, --help       show this help

Supported CLIs: codex, claude, opencode, gemini, copilot
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check" ;;
    --public-only) include_private=0 ;;
    --headless) headless=1 ;;
    --all-clis) all_clis=1 ;;
    --cli)
      [[ $# -ge 2 ]] || { echo "error: --cli requires a value" >&2; exit 2; }
      requested_clis+=("$2")
      shift
      ;;
    --platform)
      [[ $# -ge 2 ]] || { echo "error: --platform requires a value" >&2; exit 2; }
      expected_platform="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$all_clis" -eq 1 && "${#requested_clis[@]}" -gt 0 ]]; then
  echo "error: --all-clis and --cli cannot be used together" >&2
  exit 2
fi

case "$(uname -s)" in
  Darwin) platform="macos" ;;
  Linux) platform="linux" ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "error: use scripts/setup-windows.ps1 from PowerShell on Windows" >&2
    exit 2
    ;;
  *) echo "error: unsupported operating system: $(uname -s)" >&2; exit 2 ;;
esac

if [[ -n "$expected_platform" && "$expected_platform" != "$platform" ]]; then
  echo "error: this is $platform; use the matching setup entry point" >&2
  exit 2
fi

is_supported_cli() {
  local candidate="$1"
  local supported
  for supported in "${supported_clis[@]}"; do
    [[ "$candidate" == "$supported" ]] && return 0
  done
  return 1
}

append_cli() {
  local candidate="$1"
  local existing
  is_supported_cli "$candidate" || {
    echo "error: unsupported CLI: $candidate" >&2
    exit 2
  }
  if [[ "${#selected_clis[@]}" -gt 0 ]]; then
    for existing in "${selected_clis[@]}"; do
      [[ "$candidate" == "$existing" ]] && return 0
    done
  fi
  selected_clis+=("$candidate")
}

selected_clis=()
missing_clis=()
if [[ "$all_clis" -eq 1 ]]; then
  for cli_name in "${supported_clis[@]}"; do
    append_cli "$cli_name"
  done
elif [[ "${#requested_clis[@]}" -gt 0 ]]; then
  for cli_name in "${requested_clis[@]}"; do
    append_cli "$cli_name"
  done
else
  for cli_name in "${supported_clis[@]}"; do
    if command -v "$cli_name" >/dev/null 2>&1; then
      append_cli "$cli_name"
    else
      missing_clis+=("$cli_name")
    fi
  done
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
private_root="${PRIVATE_SKILLS_ROOT:-$repo_root/../manager/skills}"
if [[ -d "$private_root" ]]; then
  private_root="$(cd "$private_root" && pwd)"
fi

printf 'Agent setup: platform=%s mode=%s\n' "$platform" "$mode"
if [[ "${#selected_clis[@]}" -gt 0 ]]; then
  printf 'CLIs: %s\n' "$(IFS=,; echo "${selected_clis[*]}")"
else
  printf 'CLIs: none detected; configuring only ~/AGENTS.md\n'
fi
if [[ "${#missing_clis[@]}" -gt 0 ]]; then
  printf 'Skipped: %s\n' "$(IFS=,; echo "${missing_clis[*]}")"
fi

if [[ "$include_private" -eq 1 && -d "$private_root" ]]; then
  printf 'Private skills: %s\n' "$private_root"
else
  include_private=0
  printf 'Private skills: disabled or not found\n'
fi

instruction_args=()
[[ "$mode" == "check" ]] && instruction_args+=(--check)
instruction_args+=(--cli home)
for cli_name in "${selected_clis[@]}"; do
  instruction_args+=(--cli "$cli_name")
done

registry_args=()
use_shared=0
use_claude=0
for cli_name in "${selected_clis[@]}"; do
  if [[ "$cli_name" == "claude" ]]; then
    use_claude=1
  else
    use_shared=1
  fi
done
[[ "$use_shared" -eq 1 ]] && registry_args+=(--registry shared)
[[ "$use_claude" -eq 1 ]] && registry_args+=(--registry claude)

if [[ "${#registry_args[@]}" -gt 0 ]]; then
  skill_args=("${registry_args[@]}")
  [[ "$mode" == "check" ]] && skill_args+=(--check)
  [[ "$include_private" -eq 0 ]] && skill_args+=(--public-only)
  "$repo_root/scripts/sync-agent-skills.sh" "${skill_args[@]}"
fi

"$repo_root/scripts/sync-agent-instructions.sh" "${instruction_args[@]}"

mcp_args=()
[[ "$mode" == "check" ]] && mcp_args+=(--check)
[[ "$include_private" -eq 0 ]] && mcp_args+=(--public-only)
[[ "$headless" -eq 1 ]] && mcp_args+=(--exclude chrome-devtools)
for cli_name in "${selected_clis[@]}"; do
  mcp_args+=(--cli "$cli_name")
done
if [[ "${#selected_clis[@]}" -gt 0 ]]; then
  if command -v node >/dev/null 2>&1; then
    node "$repo_root/scripts/sync-agent-mcps.mjs" "${mcp_args[@]}"
  else
    echo "MCP sync skipped: node missing"
  fi
fi

maintenance_args=()
[[ "$mode" == "check" ]] && maintenance_args+=(--check)
[[ "$include_private" -eq 0 ]] && maintenance_args+=(--public-only)
[[ "$headless" -eq 1 ]] && maintenance_args+=(--headless)
if [[ "$all_clis" -eq 1 ]]; then
  maintenance_args+=(--all-clis)
elif [[ "${#requested_clis[@]}" -gt 0 ]]; then
  for cli_name in "${requested_clis[@]}"; do
    maintenance_args+=(--cli "$cli_name")
  done
fi
if command -v node >/dev/null 2>&1; then
  if [[ "${#maintenance_args[@]}" -gt 0 ]]; then
    node "$repo_root/scripts/sync-agent-maintenance.mjs" "${maintenance_args[@]}"
  else
    # macOS Bash 3.2 treats an empty array expansion as unbound under `set -u`.
    node "$repo_root/scripts/sync-agent-maintenance.mjs"
  fi
else
  echo "Maintenance state/hooks skipped: node missing"
fi

if [[ "$mode" == "sync" ]]; then
  if [[ "${#registry_args[@]}" -gt 0 ]]; then
    verify_skill_args=("${registry_args[@]}" --check)
    [[ "$include_private" -eq 0 ]] && verify_skill_args+=(--public-only)
    "$repo_root/scripts/sync-agent-skills.sh" "${verify_skill_args[@]}"
  fi
  verify_instruction_args=(--check --cli home)
  for cli_name in "${selected_clis[@]}"; do
    verify_instruction_args+=(--cli "$cli_name")
  done
  "$repo_root/scripts/sync-agent-instructions.sh" "${verify_instruction_args[@]}"
  if [[ "${#selected_clis[@]}" -gt 0 && -x "$(command -v node 2>/dev/null || true)" ]]; then
    verify_mcp_args=(--check)
    [[ "$include_private" -eq 0 ]] && verify_mcp_args+=(--public-only)
    [[ "$headless" -eq 1 ]] && verify_mcp_args+=(--exclude chrome-devtools)
    for cli_name in "${selected_clis[@]}"; do
      verify_mcp_args+=(--cli "$cli_name")
    done
    node "$repo_root/scripts/sync-agent-mcps.mjs" "${verify_mcp_args[@]}"
  fi
fi

echo "Agent setup complete."
