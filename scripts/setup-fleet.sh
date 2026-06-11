#!/usr/bin/env bash
# Bootstrap the agent fleet CLIs via Homebrew.
# Installs anything missing; pass --upgrade to also bump already-installed
# formulas to the latest. Idempotent: safe to re-run.
#
#   scripts/setup-fleet.sh            # install missing
#   scripts/setup-fleet.sh --upgrade  # install missing + upgrade existing
set -euo pipefail

upgrade=0
[ "${1:-}" = "--upgrade" ] && upgrade=1

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew not found — install it first: https://brew.sh" >&2
  exit 1
fi

# Fully-qualified formula ref : on-PATH command name.
fleet=(
  "edihasaj/tap/vmlab:vmlab"        # cross-OS verify orchestrator
  "edihasaj/guiport/guiport:guiport" # macOS desktop driver (AX + OCR)
  "edihasaj/abx/abx:abx"            # headless browser CLI
)

for entry in "${fleet[@]}"; do
  ref="${entry%%:*}"
  cmd="${entry##*:}"
  name="${ref##*/}"
  if brew list "$name" >/dev/null 2>&1; then
    if [ "$upgrade" = 1 ]; then
      echo "==> upgrading $name"
      brew upgrade "$ref" || true
    else
      echo "==> $name present ($("$cmd" --version 2>/dev/null | head -1))"
    fi
  else
    echo "==> installing $ref"
    brew install "$ref"
  fi
done

# abx drives Playwright's Chromium — fetch it once if the cache is empty.
if command -v abx >/dev/null 2>&1; then
  browsers="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}"
  if ! compgen -G "$browsers/chromium*" >/dev/null 2>&1; then
    echo "==> fetching Chromium for abx"
    abx install-browser || echo "warn: 'abx install-browser' failed — run it manually"
  fi
fi

cat <<'EOS'

Fleet ready:
  vmlab    — cross-OS verify orchestrator     (vmlab doctor)
  guiport  — macOS desktop driver             (grant TCC: guiport doctor --fix)
  abx      — headless browser CLI             (abx --help)

Re-run with --upgrade to bump everything to the latest.
EOS
