---
summary: "Shared MCP launcher profiles for Claude, Codex, and other agent clients."
read_when:
  - Updating global Claude or Codex MCP settings.
  - Adding or debugging an MCP server profile.
---

# MCP Profiles

Use `~/Projects/agent/bin/agent-mcp <profile>` from global MCP config. Keep AGENTS compact and keep secrets in machine-local shell config, not git.

## Profiles

- `chrome-devtools` -> `npx -y chrome-devtools-mcp@latest --autoConnect`
- `recall` -> local Recall app MCP runtime
- `zapfeed` -> `mcp-remote@0.1.38` to `https://zapfeed.io/api/mcp`
- `miro` -> `mcp-remote@latest` to `https://mcp.miro.com/` (OAuth 2.1 browser login; tokens cached in `~/.mcp-auth`)
- `slack` -> NOT via mcp-remote. Workspace Slack MCP apps commonly enforce a fixed redirect-URI allowlist and reject dynamic client registration, so mcp-remote's random-port `/oauth/callback` never matches (login loops). Use a client with native remote-MCP OAuth (Claude Code / VS Code / GitHub Copilot CLI): pin a fixed callback port + `/callback` path and have the Slack-app admin allowlist it. Workspace-specific client ids live in the private overlay.
- `atlassian` -> `mcp-remote@latest` to `https://mcp.atlassian.com/v1/sse` (Jira + Confluence; OAuth browser login, tokens cached in `~/.mcp-auth`)
- `stripe` -> `mcp-remote@latest` to `https://mcp.stripe.com` (Stripe hosted MCP; OAuth 2.1 browser login, tokens cached in `~/.mcp-auth`; no API key). Stripe's OAuth server only supports the `mcp` scope, so the profile passes `--static-oauth-client-metadata '{"scope":"mcp"}'` — without it mcp-remote's default `openid/email/profile` scopes are rejected and login fails.
- `guiport` -> `guiport serve --mcp`

Private/org-specific profiles (and their setup notes) live in the private overlay `~/Projects/manager/config/agent-mcp-private`; the launcher delegates to it automatically when the profile is defined there.

## Managed registrations

`config/mcps.json` is the public registration source. The optional private
overlay uses the same schema at `~/Projects/manager/config/mcps.json`; private
entries add new servers or override public entries by name.

The default public set contains only `chrome-devtools`. Recall owns its own MCP
registration through `recall setup`, so agent setup never overwrites it.
OAuth-heavy and project-specific profiles remain opt-in to avoid loading unused
tools in every session. The private set currently enables `glitchtip`; its
endpoint and organization-specific details stay private.

```bash
~/Projects/agent/bin/sync-agent-mcps
~/Projects/agent/bin/sync-agent-mcps --check
~/Projects/agent/bin/sync-agent-mcps --public-only --cli codex
```

The synchronizer supports Codex, Claude, Gemini, GitHub Copilot, and OpenCode.
It owns only names present in the manifests. Other user entries, Codex app MCPs,
hosted connectors/plugins, and repository `.mcp.json` files are preserved.
OpenCode JSONC configs are reported for manual merge instead of being rewritten
without their comments.

Manifest command arrays use `{repo}` and `{home}` placeholders and provide
`posix` and `windows` variants. `requires` lists executable prerequisites; a
missing prerequisite skips that registration without breaking instruction or
skill setup. `replaces` lists old registration names for automatic migrations.
Never put credentials in either manifest.

### Miro REST helper (`scripts/miro`)

Miro's hosted MCP (`miro` profile) has **no delete and no move** for items/tables, so every reposition or content fix spawns a duplicate. The `miro` CLI helper fills those gaps via the Miro REST API v2.

- Command: `~/Projects/agent/scripts/miro` (on PATH). Subcommands: `whoami`, `list <board> [--type T]`, `get <board> <id>`, `delete <board> <id...>`, `move <board> <id> --x N --y N`, `board-delete <board>`.
- Accepts full board URLs and `?moveToWidget=<id>` values directly (no manual id extraction).
- Auth: `MIRO_TOKEN` env (OAuth token from a Miro app with `boards:read` + `boards:write`). Keep a canonical copy in your password manager alongside the client id/secret used to refresh it. Create/refresh tokens at <https://miro.com/app/settings/user-profile/apps/>.
- **Tables**: MCP-created tables have REST type `data_table_format` but the **generic `/items/{id}` endpoint handles them** — `delete` and `move` both work (verified on a scratch board).
- Gotcha (MCP, not the helper): `table_create` can fail on titles containing `()` or `.`; keep table titles plain. Also compute center-anchor coords up front (tables anchor at their centre) and experiment on a scratch board, never a shared one.

## Secrets

Store reusable machine-local exports in `~/.profile` or `~/.zprofile`, for example:

```bash
export ZAPFEED_API_KEY="..."
```

The launcher sources those files at MCP startup. This fixes GUI or daemon-launched agents that do not inherit shell profile env.

Do not commit API keys, bearer tokens, 1Password item IDs, or generated MCP auth caches. If a secret is only in 1Password, pull it into the machine-local profile manually or with a targeted tmux-backed `op` flow, then restart the MCP client.

The public launcher and private GlitchTip overlay load NVM's `nvm.sh` when
`npx` is absent from a GUI or non-login shell `PATH`.

## Global Config Snippets

Claude-style JSON:

```json
{
  "mcpServers": {
    "zapfeed": {
      "command": "/Users/edi/Projects/agent/bin/agent-mcp",
      "args": ["zapfeed"]
    }
  }
}
```

Codex TOML:

```toml
[mcp_servers.zapfeed]
command = "/Users/edi/Projects/agent/bin/agent-mcp"
args = ["zapfeed"]
```

## Checks

```bash
~/Projects/agent/bin/agent-mcp --help
~/Projects/agent/bin/sync-agent-mcps --check
ssh -o BatchMode=yes -o RequestTTY=no -o RemoteCommand=none studio 'hostname'
obsidian vaults
```
