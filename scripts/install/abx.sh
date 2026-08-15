#!/usr/bin/env bash
set -euo pipefail

mode="sync"
upgrade=0
platform=""

usage() {
  cat <<'EOF'
usage: install/abx.sh [--check] [--upgrade] [--platform macos|linux]

Install the standalone edihasaj/abx CLI and its Chromium runtime.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check" ;;
    --upgrade) upgrade=1 ;;
    --platform)
      [[ $# -ge 2 ]] || { echo "error: --platform requires a value" >&2; exit 2; }
      platform="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ -z "$platform" ]]; then
  case "$(uname -s)" in
    Darwin) platform="macos" ;;
    Linux) platform="linux" ;;
    *) echo "error: unsupported abx platform: $(uname -s)" >&2; exit 2 ;;
  esac
fi
[[ "$platform" == "macos" || "$platform" == "linux" ]] || {
  echo "error: unsupported abx platform: $platform" >&2
  exit 2
}

export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

browser_root() {
  if [[ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ]]; then
    printf '%s\n' "$PLAYWRIGHT_BROWSERS_PATH"
  elif [[ "$platform" == "macos" ]]; then
    printf '%s\n' "$HOME/Library/Caches/ms-playwright"
  else
    printf '%s\n' "$HOME/.cache/ms-playwright"
  fi
}

browser_ready() {
  if [[ -n "${ABX_CHROMIUM_PATH:-}" && -x "$ABX_CHROMIUM_PATH" ]]; then
    return 0
  fi
  local root
  root="$(browser_root)"
  [[ -d "$root" ]] && compgen -G "$root/chromium*" >/dev/null
}

install_macos() {
  command -v brew >/dev/null 2>&1 || {
    echo "error: Homebrew is required to install abx on macOS: https://brew.sh" >&2
    exit 1
  }
  export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
  if brew list abx >/dev/null 2>&1; then
    if [[ "$upgrade" -eq 1 ]]; then
      echo "==> upgrading standalone abx"
      brew upgrade edihasaj/abx/abx || true
    fi
  else
    echo "==> installing standalone abx"
    brew install edihasaj/abx/abx
  fi
  hash -r 2>/dev/null || true
}

install_linux() {
  local source_dir="${ABX_SOURCE_DIR:-$HOME/Projects/abx}"
  local target="$HOME/.local/bin/abx"
  for dependency in git bun node; do
    command -v "$dependency" >/dev/null 2>&1 || {
      echo "error: $dependency is required to build standalone abx on Linux" >&2
      exit 1
    }
  done

  if [[ -d "$source_dir/.git" ]]; then
    if [[ "$upgrade" -eq 1 ]]; then
      if git -C "$source_dir" diff --quiet && git -C "$source_dir" diff --cached --quiet; then
        echo "==> updating standalone abx"
        git -C "$source_dir" pull --ff-only
      else
        echo "warn: $source_dir has local changes; building without pulling" >&2
      fi
    fi
  elif [[ -e "$source_dir" ]]; then
    echo "error: abx source path exists but is not a git checkout: $source_dir" >&2
    exit 1
  else
    echo "==> cloning standalone abx"
    mkdir -p "$(dirname "$source_dir")"
    git clone https://github.com/edihasaj/abx.git "$source_dir"
  fi

  echo "==> building standalone abx"
  (
    cd "$source_dir"
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 bun install --frozen-lockfile
    bun run build
  )
  [[ -x "$source_dir/dist/abx" ]] || {
    echo "error: abx build did not produce $source_dir/dist/abx" >&2
    exit 1
  }
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "error: kept existing non-link abx launcher: $target" >&2
    exit 1
  fi
  ln -sfn "$source_dir/dist/abx" "$target"
  hash -r 2>/dev/null || true
}

if [[ "$mode" == "check" ]]; then
  command -v abx >/dev/null 2>&1 || {
    echo "missing: standalone abx; rerun the platform setup without --check" >&2
    exit 1
  }
  abx --version >/dev/null
  browser_ready || {
    echo "missing: abx Chromium runtime; run 'abx install-browser'" >&2
    exit 1
  }
  echo "abx check complete: $(abx --version)"
  exit 0
fi

if [[ "$upgrade" -eq 1 || ! -x "$(command -v abx 2>/dev/null || true)" ]]; then
  if [[ "$platform" == "macos" ]]; then
    install_macos
  else
    install_linux
  fi
fi

command -v abx >/dev/null 2>&1 || {
  echo "error: abx installation completed but abx is not on PATH" >&2
  exit 1
}

if ! browser_ready; then
  echo "==> installing Chromium for abx"
  abx install-browser
fi

abx --version >/dev/null
browser_ready || {
  echo "error: abx Chromium runtime is still missing" >&2
  exit 1
}
echo "abx ready: $(abx --version)"
