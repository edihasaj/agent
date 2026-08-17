#!/usr/bin/env bash
# Shared launcher helpers for stdio MCP profiles.
#
# Sourced by agent/scripts/agent-mcp and by the private overlay
# manager/scripts/mcp/agent-mcp-private. Keep the logic here only — a second
# copy drifts and then breaks silently on whichever side you forgot.

MCP_REMOTE="mcp-remote@0.1.38"
PKG_ROOT="${AGENT_MCP_PKG_ROOT:-$HOME/.cache/agent-mcp/pkgs}"

load_machine_env() {
  # GUI-launched MCP clients do not source shell profiles, so pull in
  # machine-local exports here. Never store secrets in a repo.
  #
  # These profiles are written for interactive zsh and routinely include
  # third-party snippets that are not `set -eu` clean (google-cloud-sdk's
  # path.zsh.inc dies on an unbound $1). Relax both while sourcing, or the
  # launcher exits before it ever starts the server.
  set -a +eu
  for env_file in "$HOME/.profile" "$HOME/.zprofile"; do
    if [[ -r "$env_file" ]]; then
      # shellcheck source=/dev/null
      source "$env_file"
    fi
  done
  set +a -eu
}

load_npx() {
  if command -v npx >/dev/null 2>&1; then
    return
  fi

  local nvm_sh="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  if [[ -r "$nvm_sh" ]]; then
    # shellcheck source=/dev/null
    source "$nvm_sh"
  fi

  if ! command -v npx >/dev/null 2>&1; then
    echo "agent-mcp: npx missing. Install Node.js or expose it in ~/.profile or ~/.zprofile." >&2
    exit 69
  fi
}

# exec_npm_bin <pkg@version> <bin-name> [args...]
#
# Do NOT use `npx -y` for stdio MCP servers. npx runs the package under an
# `npm exec` parent that stays alive for the whole session, so every client
# pays two node processes instead of one, and the client's SIGTERM lands on
# the wrapper -- the real server is reparented to launchd and keeps running.
# An orphaned OAuth profile then retries its browser login forever.
# (2026-08-17: 161 stray procs / 6.5 GB on one machine, plus a Miro login page
# reopening on a loop.)
#
# Install the pinned version once into a cache dir, then exec node on the
# entry point directly: one process, and signals reach the server.
exec_npm_bin() {
  local spec="$1" bin="$2"
  shift 2

  local root="$PKG_ROOT/${spec//[^A-Za-z0-9._@-]/_}"
  local entry="$root/node_modules/.bin/$bin"

  if [[ ! -e "$entry" ]]; then
    load_npx
    mkdir -p "$root"
    # stdout is the MCP stdio channel; keep npm noise off it.
    if ! npm install --prefix "$root" --no-fund --no-audit --loglevel=error "$spec" >&2; then
      echo "agent-mcp: failed to install $spec into $root" >&2
      exit 69
    fi
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "agent-mcp: node missing. Install Node.js or expose it in ~/.profile or ~/.zprofile." >&2
    exit 69
  fi

  exec node "$entry" "$@"
}
