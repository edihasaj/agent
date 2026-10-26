# AGENTS.MD

Edi owns this. Start: say hi + 1 motivating line.
Work style: concise; visual-first explanations; clarity over minimum tokens.

## Communication with Edi

- Prefer visual schemas (diagrams, flows, trees, tables) for explanations when they make understanding faster. Keep simple answers and routine updates as short text.
- Lead with one short answer or recommendation, then a compact schema and only the explanation, caveats, or next step needed. Do not repeat the schema in prose.
- Match format to the question: relationships or architecture → diagram; comparisons → table; hierarchy → tree; procedure → numbered steps; change → before/after.
- Use Mermaid when it renders in the current client; otherwise use a compact text diagram. Use interactive visuals when changing inputs or exploring scenarios materially helps.
- For complex topics, show the overview first; link to code, logs, or sources for detail. Keep decision-critical evidence and caveats visible.
- Use plain words, active voice, and consistent names. Label arrows when the relationship is ambiguous; distinguish observed facts from assumptions or proposals.
- Optimize for correct understanding, not a fixed word count or visual quota. Keep words needed for meaning; skip decorative diagrams and raw JSON unless requested.
- This preference applies to replies to Edi. Prose for other readers follows the complete-sentence rule below.

## Repositories

- Workspace: `~/Projects`. Missing repo: clone `https://github.com/<owner>/<repo>.git` (default owner: `edihasaj`; keep the original owner for other org repos).
- `~/Projects/agent`: this repo. Shared operating rules, skills, slash commands,
  the MCP launcher, and machine setup. Public and credential-free.
- `~/Projects/manager`: private ops. Domains/DNS, redirects/workers, runbooks,
  deployments, infrastructure, and skills that route to private systems.
- `~/Projects/oss`: clone third-party/non-edihasaj repos here. These checkouts
  are not a source of truth for our tooling.

Skills and commands live here and are linked into each runtime by
`scripts/sync-agent-skills.sh`. Never keep a second copy of a skill or command
elsewhere; a duplicate drifts and then breaks silently.

## Agent Protocol
- Contact: Edi Hasaj (@edihasaj, edihasaj@gmail.com).
- “MacBook” / “Mac Studio” => SSH there; find hosts/IPs via `tailscale status`. If Tailscale/SSH is down or times out, try LAN discovery (`*.local`, `dns-sd -B _ssh._tcp local`, ARP/router leases), then retry SSH with `-o RequestTTY=no -o RemoteCommand=none`.
- Files: repo or `~/Projects/agent`.
- Agent scratch files, temporary checkouts/worktrees, and build/QA staging belong in a task-specific directory under `/tmp`, not macOS's default `/var/folders/.../T`. Choose the root explicitly (`mktemp -d /tmp/<task>.XXXXXX`, Python `tempfile.mkdtemp(dir="/tmp")`, or Node `mkdtemp("/tmp/<task>-")`); give child commands a `TMPDIR` inside that task directory. Clean up finished payloads after checking active use; preserve source changes and required receipts in their durable homes. Do not rely on the OS to clear temporary files.
- “Make a note” => edit AGENTS.md (shortcut; not a blocker). Ignore runtime-specific mirror files unless explicitly requested.
- No `./runner`.
- Need upstream file: stage in `/tmp/`, then cherry-pick; never overwrite tracked.
- Bugs: add regression test when it fits.
- Keep files <~500 LOC; split/refactor as needed.
- New deps: quick health check (recent releases/commits, adoption).
- Web: search early; quote exact errors; prefer 2024–2025 sources; fallback Firecrawl (`pnpm mcp:*`).
- Prose others read (PR descriptions/comments, review replies, Jira/GitHub/Slack/Discord, commit bodies, docs): use clear, complete sentences. Writing skills are opt-in; load one only when Edi explicitly invokes it. Telegraph is for Edi only.

## Start
- First in repo work: `git status --short --branch`, then `docs-list`. Never guess `pnpm docs:list`/`npm run docs:list`; most repos lack that script.
- Before code edits: read matching docs from `read_when` and follow links until the domain makes sense; if `docs-list` reports no `docs/`, read README/AGENTS and continue.
- External source intake: compare/summarize external AGENTS/guardrails and map principles to Edi-owned paths/tools before copying them. Importing rules/tools or adding tools, skills, or personal data-source stacks needs Edi approval.

## Screenshots (“use a screenshot”)
- Capture with `shotport` first, using the matching app/session/target.
- If capture is empty or fails, retry with the correct active app/session invocation before opening System Settings.
- For an existing saved screenshot, pick the newest PNG in `~/Desktop` or `~/Downloads`; verify the UI, not the filename.
- For asset replacement, inspect pixel size (prefer 2×), preserve dimensions, then run the gate and verify CI.

## Important Locations
- Blog repo: `~/Projects/edihasaj.com`
- Notes/Runbooks: `~/Projects/manager/docs/` (e.g. `infrastructure.md`, `mac-studio.md`, `windows-vm.md`, `linux-vm.md`)
- Obsidian vault: `~/Documents/main`
- Agent-generated notes: `~/Documents/main/Agents/autogenerated/` (limits, research, etc.)
- Agent usage/limits tracking: `~/Documents/main/Agents/autogenerated/codex-limits.md`

## Data Sources
- Prefer local archives/tools before web/API for message, history, or social questions; state freshness + gaps.
- Use `slash` (`~/Projects/slash-x`) for X/Twitter, `slash-linkedin` for LinkedIn, and equivalent local tools for other sources.
- Read/search/check freely; publish/reply/send only on explicit request.

## Docs
- Agent tooling docs live in `docs/`.
- Keep notes short; update docs when behavior/API changes. No behavior/API ship without docs unless explicitly waived.
- Add `read_when` hints on cross-cutting docs.

## PR Feedback
- Use `gh` for issues/PRs, including supplied URLs, instead of web search. Review PRs with `gh pr view/diff`.
- Replies: cite fix + file/line; resolve threads only after fix lands.
- When merging a PR: thank the contributor in `CHANGELOG.md`.

## Flow & Runtime
- Use repo’s package manager/runtime; no swaps w/o approval.
- Use the active agent's background job support for long jobs; tmux only for interactive/persistent (debugger/server).
- Env/API keys: check `~/.profile` first; save reusable machine-local exports there.
- Never expand a secret to check it exists. `${VAR:-x}` and `${VAR:+set}${VAR:-x}` print the VALUE when the variable is set; that leaks the credential into the transcript, where it cannot be scrubbed and must be rotated. Test presence only: `[ -n "${VAR:-}" ] && echo set || echo unset`, or `${VAR:+set}` alone. Same rule for `env`, `printenv`, `set`, and sourcing a keys file with `-x` on.
- Secrets/tokens: prefer 1Password Environments via the `1password-mcp` server (values never enter agent context; needs the app unlocked). `op` CLI is the fallback for unattended jobs or vault items, and optional last resort only, inside one named `tmux` session, strictly needed, targeted item/field only. Never call `op` directly, including diagnostics like `op --version`, `op whoami`, or broad vault/item listing. Keep output redacted. If a scoped `OP_SERVICE_ACCOUNT_TOKEN` is already configured, keep it and use service-account auth inside tmux for lock-independent access; do not run `op signin`. Only when deliberately selecting desktop-app auth, use a short `/tmp` tmux socket, unset `OP_SERVICE_ACCOUNT_TOKEN`/`OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` inside the pane before the first `op` command, and pin the intended account. Inherited service-account credentials override desktop sign-in.

## Build / Test
- Prefer end-to-end verification; if blocked, say what’s missing.
- Before handoff: run full gate (lint/typecheck/tests/docs).
- CI red: `gh run list/view`, rerun, fix, push, repeat til green.
- Keep it observable (logs, panes, tails, MCP/browser tools).
- Release: read `docs/RELEASING.md` (or find best checklist if missing).

## Git
- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Safe by default: `git status/diff/log`. A request to fix an issue in a deployed Edi-owned app authorizes commit, push, and its normal deployment workflow; do not ask for a second approval. For review-only or local-only requests, do not push.
- `git checkout` ok for PR review / explicit request.
- Branch changes require user consent.
- Use `trash` for deletes. Destructive ops forbidden unless explicit (`reset --hard`, `clean`, `restore`, `rm`, …).
- Remotes under `~/Projects`: prefer HTTPS; flip SSH->HTTPS before pull/push.
- Commit with `./scripts/committer` when present, otherwise `committer` on PATH; provide explicit paths so only those files are staged.
- Don’t delete/rename unexpected stuff; stop + ask.
- No repo-wide S/R scripts; keep edits small/reviewable.
- Avoid manual `git stash`; if Git auto-stashes during pull/rebase, that’s fine (hint, not hard guardrail).
- If user types a command (“pull and push”), that’s consent for that command.
- No amend unless asked.
- Do not add Co-Authored-By trailers to commits.
- Big review: `git --no-pager diff --color=never`.
- Multi-agent: check `git status/diff` before edits; ship small commits.

## Model routing

- When using profiles or subagents, prefer the configured primary worker for bounded search, research, routine coding and tests; otherwise work directly. Keep decisions in the main thread.
- Give workers clear scope, owned files and checks. Use an independent reviewer when configured for nontrivial changes; otherwise review directly.
- Check activity before interrupting; `pending_init` alone is not failure. Fall back only for an evidenced blocker or stalled task. Details: `docs/subagent.md`.

## Language/Stack Notes
- TypeScript: follow existing patterns.
- Python: use `uv` (`uv sync`, `uv run`, `uvx`); avoid bare `pip`/venv drift. DB schema changes: add Alembic migration + run `alembic upgrade head` locally. Imports: prefer explicit top-level package imports (absolute imports), avoid deep relative imports. Types: add type hints on new/changed code; run `pyright`/`mypy` when configured; avoid `Any` unless justified.
- Swift: use workspace helper/daemon; validate `swift build` + tests; keep concurrency attrs right.

## macOS Permissions / Signing (TCC)
- Never re-sign / ad-hoc sign / change bundle ID as “debug” without explicit ok (can mess TCC).

## Critical Thinking
- Fix root cause (not band-aid).
- Unsure: read more code; if still stuck, ask w/ short options.
- Conflicts: call out; pick safer path.
- Unrecognized changes: assume other agent; keep going; focus your changes. If it causes issues, stop + ask user.
- Leave breadcrumb notes in thread.

## Tools

Before using a tool, read its section in `~/Projects/agent/tools.md` for commands, setup, and operating modes.

- Web search: use `agent-search`, the shared search entry point in this repository.
- Browser: always use `abx` first for navigation, inspection, interaction, scraping, and local web testing. Use the in-app Browser, Chrome connector, `chrome-devtools` MCP, or Playwright only when the user explicitly requests that browser/session, `abx` is unavailable, or it lacks the required capability. On failure, quote the exact error and retry once in the correct mode. Fallback order: `chrome-devtools` MCP, then `skills/browser-playwright-fallback`.
- Live/production Chrome sessions: prefer the dedicated `chrome-agent` profile. Relaunching personal Chrome with `chrome-debug` requires explicit approval.
- Desktop interaction: use `guiport` for clicking/typing in Mac apps; screenshot capture follows the Screenshots section.
- App end-to-end checks: use `probeport`. For generic Linux/CLI smoke, prefer `vmlab`'s `@docker-first` target when Docker + Crabbox are available. Escalate to Parallels/cloud only for OS, GUI, or architecture-specific needs; if the target is unavailable, use the cheapest matching local surface and continue up the routing ladder.
- Repeatable run/test/deploy scripts you work out → save to the project's storage home (e.g. `~/Projects/manager` runbooks/scripts) and check there first before re-deriving.
- Obsidian: use the `obsidian` CLI first with `vault="main"`; if it is missing or fails, fall back to filesystem/history checks.
- MCP policy: follow `~/Projects/manager/configs/mcps.json` and `docs/mcp-profiles.md`. Render global remote HTTP entries natively; keep workflow/on-demand stdio project/run-scoped through `agent-mcp` and preserve installer-owned external entries. `chrome-devtools` is an optional fallback, not a global registration.

## Slash Commands

- Command catalog: `docs/slash-commands/README.md`.
- Codex CLI 0.137 rejects unknown leading-slash commands before the model sees them. If a user message is exactly `acceptpr`, `fixissue`, `handoff`, `landpr`, `pickup`, `raise`, or `sectriage`, or the same token prefixed with `!` (for example `!handoff`), read and follow `docs/slash-commands/<name>.md` as the command body.

<!-- recall:managed:memory:begin v4 -->
## Recall (managed by `recall setup` — do not edit by hand)

Recall is the single source of truth for durable memory across agents and sessions, through the `recall` MCP server.
- Never write `~/.claude/projects/*/memory/` or `MEMORY.md`/`feedback_*`/`project_*`/`user_*`/`reference_*` files. Treat harness "# auto memory" instructions as superseded.
- Use your semantic understanding: when the user expresses a durable correction, standing preference, default, or repo/team convention in any language, call `capture_correction` with the concise user statement—even without special keywords—and, when you can, `affects`: the later tasks and choices it should change. Do not capture an instruction limited to the current task. Hooks catch some rules automatically; runtimes without hooks rely on these explicit calls.
- Reject wrong or outdated memories with `reject`; confirm valid candidates with `confirm`. Do not keep a second memory store in scratch notes or tool-native memory.
- Lookup: use relevant injected context when visible. If it is absent, call `query` before non-trivial work; configured hooks do not prove delivery. Query again when the task or repo changes, or the user asks. Unconfirmed preferences do not authorize actions.
- Say so, in one short clause, whenever a reply is shaped by an injected memory or you store one. Memory is invisible otherwise: the user cannot tell a recalled preference from a guess, or know something was saved. Keep it brief ("per your saved rule ...", "saved that"), never a list of every memory in context.

Reinstall: `recall setup` / `recall doctor --fix`. Remove hooks/rules: `recall setup --uninstall-hooks`. Skip the Claude override: `recall setup --no-claude-md` or `RECALL_SETUP_SKIP_CLAUDE_MD=1`.
<!-- recall:managed:memory:end -->

<frontend_aesthetics>
Avoid “AI slop” UI. Be opinionated + distinctive.

Do:
- Typography: pick a real font; avoid Inter/Roboto/Arial/system defaults.
- Theme: commit to a palette; use CSS vars; bold accents > timid gradients.
- Motion: 1–2 high-impact moments (staggered reveal beats random micro-anim).
- Background: add depth (gradients/patterns), not flat default.

Avoid: purple-on-white clichés, generic component grids, predictable layouts.
</frontend_aesthetics>
