#!/usr/bin/env bash
# First-run setup for Edi's local agent machine.
#
# Installs the shared fleet, then walks permission-gated tools one at a time.
# Re-run anytime; it is idempotent and waits for manual macOS grants.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upgrade=0
pull=1

usage() {
  cat <<'EOS'
Usage: scripts/setup-agent-machine.sh [--upgrade] [--no-pull]

Installs/updates agent CLIs and verifies local permissions:
  1. pull agent-scripts
  2. setup fleet tools (vmlab, guiport, abx, shotport)
  3. fetch abx browser runtime
  4. walk macOS Accessibility/Screen Recording prompts
  5. run cheap smoke checks

Flags:
  --upgrade   upgrade already-installed Homebrew tools
  --no-pull   skip git pull for agent-scripts
  -h, --help  show this help
EOS
}

while [ $# -gt 0 ]; do
  case "$1" in
    --upgrade) upgrade=1 ;;
    --no-pull) pull=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

step() {
  printf '\n==> %s\n' "$1"
}

warn() {
  printf 'warn: %s\n' "$1" >&2
}

have() {
  command -v "$1" >/dev/null 2>&1
}

wait_for_enter() {
  if [ -t 0 ]; then
    printf 'Press Enter after granting it, or Ctrl-C to stop... '
    read -r _
  else
    echo "Non-interactive shell; grant manually, then rerun this script." >&2
    return 1
  fi
}

run_doctor_until_ok() {
  local name="$1"
  local fix_cmd="$2"
  local check_cmd="$3"
  local instructions="$4"

  step "$name"
  if bash -lc "$check_cmd"; then
    return 0
  fi

  echo "$instructions"
  bash -lc "$fix_cmd" || true

  while ! bash -lc "$check_cmd"; do
    wait_for_enter
  done
}

cd "$repo_dir"

if [ "$pull" = 1 ]; then
  step "pull agent-scripts"
  if git diff --quiet && git diff --cached --quiet; then
    git pull --ff-only || warn "agent-scripts pull failed"
  else
    warn "agent-scripts has local changes; skipped pull"
  fi
fi

step "install fleet"
if [ "$upgrade" = 1 ]; then
  "$repo_dir/scripts/setup-fleet.sh" --upgrade
else
  "$repo_dir/scripts/setup-fleet.sh"
fi

step "PATH hint"
profile_line='export PATH="$HOME/Projects/agent-scripts/scripts:$HOME/Projects/agent-scripts/bin:$PATH"'
if [ -f "$HOME/.profile" ] && grep -Fq 'Projects/agent-scripts/scripts' "$HOME/.profile"; then
  echo "~/.profile already exposes agent-scripts helpers"
else
  echo "Add this to ~/.profile for committer/docs-list/agent-mcp in future shells:"
  echo "  $profile_line"
fi

if have guiport; then
  run_doctor_until_ok \
    "guiport macOS permissions" \
    "guiport doctor --fix" \
    "guiport doctor >/dev/null 2>&1" \
    "Grant Accessibility and Screen Recording to the invoking terminal/tool in System Settings."
else
  warn "guiport missing after setup"
fi

if have abx; then
  step "abx smoke"
  abx --help >/dev/null
  echo "abx ok"
else
  warn "abx missing after setup"
fi

if have shotport; then
  run_doctor_until_ok \
    "shotport Screen Recording" \
    "shotport doctor" \
    "shotport doctor >/dev/null 2>&1" \
    "Approve shotport in System Settings → Privacy & Security → Screen Recording."
  step "shotport smoke"
  shotport browser https://example.com --text-only >/dev/null || warn "shotport browser smoke failed"
  shotport desktop --budget 900 --jpeg >/dev/null || warn "shotport desktop smoke failed"
  echo "shotport ok"
else
  warn "shotport missing after setup"
fi

if have vmlab; then
  step "vmlab smoke"
  vmlab --help >/dev/null
  echo "vmlab ok"
else
  warn "vmlab missing after setup"
fi

cat <<'EOS'

Agent machine ready.
If any macOS permission was just granted, restart the terminal/app that runs agents.
EOS
