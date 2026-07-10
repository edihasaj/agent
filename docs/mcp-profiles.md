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
- `slack` -> `mcp-remote@latest` to `https://mcp.slack.com/mcp` (public OAuth client id; browser login, tokens cached in `~/.mcp-auth`)
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
