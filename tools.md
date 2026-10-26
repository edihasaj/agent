# Tool catalog

Command usage and setup for the tools selected by `AGENTS.MD`. Run each command
with `--help` for its current surface.

| Need | Tool | Notes |
| --- | --- | --- |
| Web search | `agent-search` | Private SearXNG by default; paid providers require explicit selection |
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
| Documentation inventory | `docs-list` | Lists repository docs and their `read_when` hints |
| Xcode project generation | `xcodegen` | Generates projects from YAML specifications |
| Native debugging | `lldb` | Attaches to a running app to inspect its state |
| Notes | `obsidian` | Operates the `main` vault |
| Persistent terminals | `tmux` | Holds interactive sessions |
| Editor | `code <path>` | Opens a file or directory |

## Shell PATH

`committer`, `op`, `brew`, `uv`, and `gh` need to resolve in non-login shells,
including tmux panes. The guarded Homebrew + `~/.local/bin` PATH block belongs
in `~/.zshenv`, the only zsh rc file read by non-login, non-interactive shells.
Zsh does not read `~/.profile`; exports kept only in `~/.zprofile` or `~/.zshrc`
do not reach those panes. On a new machine, copy the guarded PATH block from
the existing machine's `~/.zshenv`.

## Commits and deletion

The PATH commit helper lives at `~/.local/bin/committer`. Its syntax is:

```bash
committer "docs: clarify shared instructions" AGENTS.MD tools.md
trash <path>
```

## Documentation inventory

`docs-list` is linked into `~/.local/bin` by `scripts/sync-agent-helpers.sh`.
It runs the repository's own `docs:list` script with its package manager when
present, otherwise its `bin/docs-list`, otherwise lists `docs/` with
`read_when` hints. If there is no `docs/`, it reports that and exits 0.

## Web search

`agent-search` is the shared entry point for agent web research. It delegates
to the canonical `skills/web-search/search.js` implementation.
`scripts/sync-agent-helpers.sh` installs its link into `~/.local/bin`.

```bash
agent-search "query" -n 5
agent-search "query" --profile code
agent-search "query" --content
```

Private SearXNG is the default. Its endpoint and token come from the owner-only
`~/.config/agent-search/client.json`, outside this public repository. Missing
configuration or service errors do not switch to a paid provider.
`--provider brave` explicitly selects the paid API and requires `BRAVE_API_KEY`.
`SEARCH_PROVIDER` can explicitly select a provider for a process.

Install the existing helper dependencies with
`npm ci --prefix ~/Projects/agent/skills/web-search` when needed. The skill's
`content.js` still extracts known URLs without performing a search.

## Browser

The standalone repository is `~/Projects/abx`. Installation and updates use:

```bash
brew install edihasaj/abx/abx
brew upgrade abx
abx install-browser
abx --help
```

`abx install-browser` fetches Chromium on a new machine. For live browser,
production-session, or real-Chrome work, start the dedicated profile and use
its CDP endpoint:

```bash
~/Projects/abx/scripts/chrome-agent start
ABX_LIVE_CDP_URL=http://127.0.0.1:9223 abx live <cmd>
```

`~/Projects/abx/scripts/chrome-debug` relaunches personal Chrome; its approval
requirement is in `AGENTS.MD`.

## Screenshots

`shotport` extracts accessibility text, including scrolled-out content, and
writes a budget-resized image. Its output includes a summary line and a path.
Open the image only when pixels are needed.

```bash
shotport --help
shotport window
shotport app <name>
shotport desktop
shotport browser <url>
sips -g pixelWidth -g pixelHeight <file>
```

`window` captures the frontmost app and takes no app name. Use the matching
`ios` or `android` target for mobile capture. Available flags include
`--text-only`, `--budget <tok>`, `--webp`, and `--json`.

## Desktop interaction

`guiport --help` describes its find/click/type commands. It auto-pastes into
Electron/WebView fields such as Teams, Slack, VS Code, and browsers so typing
does not drop characters.

## End-to-end checks

On a machine running Wieldr, `probeport` and `autoreview` execute the engines
packaged in the current Wieldr release, so commands share its configuration,
state, and evidence. Other machines fall back to the `~/Projects/probeport`
checkout.

Probeport drives browser, VM, desktop, and native gates, and collects evidence
for its dashboard. Use the change flow for a specific app check and the explore
flow for broad exploration:

```bash
probeport run change --repo <repo>
probeport run explore --repo <repo> --url <url>
vmlab run @docker-first -- <command>
```

## GitHub

PR inspection, comments, and CI use these interfaces:

```bash
gh pr view --json number,title,url --jq '"PR #\(.number): \(.title)\n\(.url)"'
gh pr diff
gh issue view <url> --comments -R owner/repo
gh pr view <url> --comments --files -R owner/repo
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate
gh run list
gh run view <run-id>
```

## Apple development

`xcp --help` covers Xcode targets, groups, files, build settings, and assets.
`xcodegen --help` covers generating projects from YAML specifications.

Use `lldb` in a tmux session to attach to a running native app and inspect state.
Simulator commands include:

```bash
axe list-simulators
axe describe-ui --udid <udid>
axe tap --udid <udid> -x <x> -y <y>
```

`axe` also supports typing and hardware buttons.

## Obsidian

Pass `vault="main"` to `obsidian` commands to select the main vault.

## Terminal sessions

```bash
tmux new -d -s agent-shell
tmux attach -t agent-shell
tmux list-sessions
tmux kill-session -t agent-shell
```

## Repository entry points

- `bin/agent` — setup diagnostics
- `bin/agent-mcp` — public MCP profile launcher
- `bin/sync-agent-mcps` — reconcile private manager MCP registrations
- `scripts/setup-agent.sh` — portable POSIX setup core
- `scripts/setup-agent-machine.sh` — guided macOS workstation bootstrap
- `scripts/sync-agent-helpers.sh` — install and check shared helper commands
- `scripts/sync-agent-settings.mjs` — pin owned agent CLI settings (commit co-author trailers off)

Launch an owned MCP profile with `~/Projects/agent/bin/agent-mcp <profile>`.
