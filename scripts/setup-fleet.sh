#!/usr/bin/env bash
# Bootstrap the agent fleet and QA CLIs.
# Installs anything missing; pass --upgrade to also bump already-installed
# formulas to the latest. Idempotent: safe to re-run.
#
#   scripts/setup-fleet.sh            # install missing
#   scripts/setup-fleet.sh --upgrade  # install missing + upgrade existing
set -euo pipefail

upgrade=0
[ "${1:-}" = "--upgrade" ] && upgrade=1
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew not found — install it first: https://brew.sh" >&2
  exit 1
fi

# Homebrew 6.0 enforces tap-trust by default, which fails the build subprocess
# (bare exit 1) for our unbottled taps (edihasaj/*) and doesn't honor `brew
# trust`/trust.json on that path. Scope the bypass to THIS script's brew calls
# so fleet installs work everywhere without a machine-wide change.
export HOMEBREW_NO_REQUIRE_TAP_TRUST=1

# Refresh tap metadata before upgrading so brew actually sees new releases
# (a stale local tap clone otherwise reports "already installed").
if [ "$upgrade" = 1 ]; then
  echo "==> brew update"
  brew update >/dev/null 2>&1 || true
fi

# Fully-qualified formula ref : on-PATH command name.
fleet=(
  "edihasaj/tap/vmlab:vmlab"        # cross-OS verify orchestrator
  "edihasaj/guiport/guiport:guiport" # macOS desktop driver (AX + OCR)
)

if ! command -v bun >/dev/null 2>&1; then
  echo "==> installing bun"
  brew install bun
fi

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

  # Self-heal a shadowed keg: an old install-script can leave bin/<cmd>
  # pointing at an app bundle / stale binary, so brew upgrades the keg but the
  # wrong version stays on PATH. Relink the brew keg so it wins.
  kegver="$(brew list --versions "$name" 2>/dev/null | awk '{print $2}')"
  pathver="$("$cmd" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [ -n "$kegver" ] && [ "$kegver" != "$pathver" ]; then
    echo "    note: $cmd on PATH ($pathver) shadows brew keg ($kegver) — relinking"
    brew link --overwrite --force "$name" >/dev/null 2>&1 || true
    hash -r 2>/dev/null || true
    pathver="$("$cmd" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    [ "$kegver" = "$pathver" ] || echo "    warn: $cmd still $pathver after relink — a non-brew copy earlier in PATH may shadow it"
  fi
done

abx_args=(--platform macos)
[[ "$upgrade" -eq 1 ]] && abx_args+=(--upgrade)
"$repo_root/scripts/install/abx.sh" "${abx_args[@]}"

# shotport is open-source but source-built (no Homebrew bottle yet): clone the
# public repo into ~/Projects and install the standalone compiled binary into
# /opt/homebrew/bin via `bun run install:local`.
if command -v shotport >/dev/null 2>&1 && [ "$upgrade" != 1 ]; then
  echo "==> shotport present ($(shotport --version 2>/dev/null | head -1))"
else
  shotport_dir="$HOME/Projects/shotport"
  if [ -d "$shotport_dir/.git" ]; then
    echo "==> updating shotport"
    git -C "$shotport_dir" pull --ff-only || echo "warn: shotport pull failed — resolve $shotport_dir manually"
  else
    echo "==> cloning shotport"
    mkdir -p "$HOME/Projects"
    git clone https://github.com/edihasaj/shotport.git "$shotport_dir"
  fi

  if [ -d "$shotport_dir" ]; then
    echo "==> building shotport"
    (cd "$shotport_dir" && bun install && bun run install:local)
  fi
fi

# Probeport is private and source-built. The stable agent wrapper keeps
# invocation identical across agent runtimes while this checkout owns the
# versioned implementation and dashboard assets.
if ! command -v node >/dev/null 2>&1; then
  echo "==> installing Node.js for Probeport"
  brew install node
fi
if ! command -v pnpm >/dev/null 2>&1; then
  echo "==> installing pnpm for Probeport"
  brew install pnpm
fi

probeport_dir="$HOME/Projects/probeport"
if [ -d "$probeport_dir/.git" ]; then
  if [ "$upgrade" = 1 ]; then
    if git -C "$probeport_dir" diff --quiet &&
      git -C "$probeport_dir" diff --cached --quiet; then
      echo "==> updating Probeport"
      git -C "$probeport_dir" pull --ff-only ||
        echo "warn: Probeport pull failed — resolve $probeport_dir manually"
    else
      echo "warn: Probeport has local changes — skipped pull"
    fi
  fi
else
  echo "==> cloning Probeport"
  mkdir -p "$HOME/Projects"
  git clone https://github.com/edihasaj/probeport.git "$probeport_dir"
fi

if [ -d "$probeport_dir" ]; then
  echo "==> building Probeport"
  (cd "$probeport_dir" && pnpm install --frozen-lockfile && pnpm build)
fi

agent_scripts_dir="$repo_root"
probeport_wrapper="$agent_scripts_dir/bin/probeport"
probeport_link="$HOME/.local/bin/probeport"
mkdir -p "$HOME/.local/bin"
if [ ! -e "$probeport_link" ] || [ -L "$probeport_link" ]; then
  ln -sfn "$probeport_wrapper" "$probeport_link"
elif [ "$probeport_link" != "$probeport_wrapper" ]; then
  echo "warn: $probeport_link exists and is not a symlink — kept it unchanged"
fi

cat <<'EOS'

Fleet ready:
  vmlab    — cross-OS verify orchestrator     (vmlab doctor)
  guiport  — macOS desktop driver             (grant TCC: guiport doctor --fix)
  abx      — headless browser CLI             (abx --help)
  shotport — token-cheap screenshots          (shotport --help)
  probeport — evidence-first exhaustive QA    (probeport doctor --deep)

Re-run with --upgrade to bump everything to the latest.
EOS
