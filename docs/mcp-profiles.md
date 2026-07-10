---
summary: "Shared MCP launcher profiles for Claude, Codex, and other agent clients."
read_when:
  - Updating global Claude or Codex MCP settings.
  - Adding or debugging an MCP server profile.
---

# MCP Profiles

Use `~/Projects/agent-scripts/bin/agent-mcp <profile>` from global MCP config. Keep AGENTS compact and keep secrets in machine-local shell config, not git.

## Profiles

- `chrome-devtools` -> `npx -y chrome-devtools-mcp@latest --autoConnect`
- `recall` -> local Recall app MCP runtime
- `zapfeed` -> `mcp-remote@0.1.38` to `https://zapfeed.io/api/mcp`
- `miro` -> `mcp-remote@latest` to `https://mcp.miro.com/` (OAuth 2.1 browser login; tokens cached in `~/.mcp-auth`)
- `slack` -> NOT via mcp-remote. The redacted Slack MCP app enforces a fixed redirect-URI allowlist and rejects dynamic client registration, so mcp-remote's random-port `/oauth/callback` never matches (login loops). Use a client with native remote-MCP OAuth (Claude Code / VS Code / GitHub Copilot CLI). Claude Code: `claude mcp add --transport http --client-id redacted --callback-port 8090 -s user slack https://mcp.slack.com/mcp`, then have the Slack-app admin allowlist `http://localhost:8090/callback` (note path is `/callback`, not `/oauth/callback`).
- `atlassian` -> `mcp-remote@latest` to `https://mcp.atlassian.com/v1/sse` (Jira + Confluence; OAuth browser login, tokens cached in `~/.mcp-auth`)
- `kb` -> redacted Knowledge Base local stdio MCP: `uv run --directory ~/Projects/redacted/redacted-knowledge kb serve-mcp` (tools: `kb_search`, `kb_raw`, `kb_check`, `kb_review`, ...; `KB_DB_PATH` pinned to the repo `.poc.db`)
- `stripe` -> `mcp-remote@latest` to `https://mcp.stripe.com` (Stripe hosted MCP; OAuth 2.1 browser login, tokens cached in `~/.mcp-auth`; no API key). Stripe's OAuth server only supports the `mcp` scope, so the profile passes `--static-oauth-client-metadata '{"scope":"mcp"}'` — without it mcp-remote's default `openid/email/profile` scopes are rejected and login fails.
- `guiport` -> `guiport serve --mcp`

## Secrets

Store reusable machine-local exports in `~/.profile` or `~/.zprofile`, for example:

```bash
export ZAPFEED_API_KEY="..."
```

The launcher sources those files at MCP startup. This fixes GUI or daemon-launched agents that do not inherit shell profile env.

Do not commit API keys, bearer tokens, 1Password item IDs, or generated MCP auth caches. If a secret is only in 1Password, pull it into the machine-local profile manually or with a targeted tmux-backed `op` flow, then restart the MCP client.

## Global Config Snippets

Claude-style JSON:

```json
{
  "mcpServers": {
    "zapfeed": {
      "command": "/Users/edi/Projects/agent-scripts/bin/agent-mcp",
      "args": ["zapfeed"]
    }
  }
}
```

Codex TOML:

```toml
[mcp_servers.zapfeed]
command = "/Users/edi/Projects/agent-scripts/bin/agent-mcp"
args = ["zapfeed"]
```

## Checks

```bash
~/Projects/agent-scripts/bin/agent-mcp --help
ssh -o BatchMode=yes -o RequestTTY=no -o RemoteCommand=none studio 'hostname'
obsidian vaults
```
