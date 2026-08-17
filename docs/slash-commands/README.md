---
summary: 'Index of slash commands (prompts) and where they live.'
read_when:
  - Auditing or updating slash command docs.
---
# Slash Commands

Source of truth: this directory.

Sync targets:
- Claude prompt directories symlink `<name>.md` -> `docs/slash-commands/<name>.md`.
- Codex prompt directories get generated `<name>.md` files with Codex-safe front matter and the shared command body.
- Targets: `~/.claude/commands` (Claude global), `~/.codex/prompts` (Codex global), `.claude/commands` (Claude project), `.codex/prompts` (Codex project mirror).

Run `scripts/sync-slash-commands.sh` after adding/removing a command — it updates all of the above (idempotent). Do not hand-edit runtime-specific command files.

Codex loads custom prompts from `~/.codex/prompts`; the project `.codex/prompts` mirror is for repo-local discoverability and parity with Claude project commands. Restart Codex or open a new Codex chat after syncing prompt changes.

Codex CLI 0.137 does not expose these custom prompts as native slash-menu commands, and rejects unknown leading-slash commands before the model sees them. `AGENTS.MD` carries a fallback rule: in Codex, send `handoff` or `!handoff` instead of `/handoff`; send `pickup` or `!pickup` instead of `/pickup`; same pattern for the other command names.

## Available commands
- `/acceptpr` — Land one PR end-to-end (changelog + thanks, lint, merge, back to main).
- `/fixissue` — Fix an issue end-to-end (tests, changelog, commit, push, comment, close).
- `/handoff` — Capture current state for the next agent (running sessions, tmux targets, blockers, next steps).
- `/landpr` — Land PR via temp-branch rebase + full gate (`pnpm lint && pnpm build && pnpm test`) before commit; merge via `gh pr merge` (rebase/squash) and verify GitHub state = `MERGED` (never `CLOSED`).
- `/pickup` — Rehydrate context when starting work (status, tmux sessions, CI/PR state).
- `/raise` — If changelog is released, open next patch `Unreleased` section (commit + push `CHANGELOG.md`).
- `/sectriage` — Finish GHSA triage end-to-end (land fix, run gates, patch advisory via `gh api`, ready to publish later).

See the individual files in this directory for details.
