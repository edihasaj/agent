#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

node --check scripts/agent-cli.mjs
node --check scripts/sync-agent-maintenance.mjs
bash -n bin/agent scripts/agent-mcp scripts/setup-agent.sh scripts/sync-agent-helpers.sh scripts/install/abx.sh scripts/git-hooks/post-sync-check
node --test test/*.test.mjs
