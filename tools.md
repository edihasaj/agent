# Tool catalog

Preferred local interfaces for common agent work. Run each command with
`--help` for its current surface.

| Need | Tool | Notes |
| --- | --- | --- |
| Browser automation | `abx` | First choice for navigation, inspection, scraping, and local web tests |
| Screenshots | `shotport` | Captures apps, desktop, browser output, and accessibility text |
| macOS interaction | `guiport` | Finds, clicks, and types in visible applications |
| End-to-end testing | `probeport` | Routes browser, VM, desktop, and native evidence collection |
| VM or container checks | `vmlab` | Cross-platform smoke and compatibility runs |
| Xcode project edits | `xcp` | Targets, groups, build settings, assets, and project structure |
| Simulator control | `axe` | Describes UI, taps, types, and sends hardware actions |
| GitHub | `gh` | Issues, pull requests, releases, and CI |
| Safe deletion | `trash` | Recoverable removal instead of direct deletion |
| Scoped commits | `committer` | Commits exactly the paths provided; setup installs it under `~/.local/bin` |

Repository entry points:

- `bin/agent` — setup diagnostics
- `bin/agent-mcp` — public MCP profile launcher
- `bin/sync-agent-mcps` — reconcile private manager MCP registrations
- `scripts/setup-agent.sh` — portable POSIX setup core
- `scripts/setup-agent-machine.sh` — guided macOS workstation bootstrap
- `scripts/sync-agent-helpers.sh` — install and check shared helper commands
- `scripts/sync-agent-settings.mjs` — pin owned agent CLI settings (commit co-author trailers off)
