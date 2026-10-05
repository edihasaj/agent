---
summary: "Pull-triggered and on-demand reconciliation of shared agent configuration across runtimes."
read_when:
  - Changing automatic agent or manager repository updates.
  - Troubleshooting why a pull did not update skills, instructions, or MCPs.
  - Diagnosing stale skills, MCP policy, instructions, or runtime settings.
  - Adding a private, machine-gated instruction overlay.
---

# Agent Sync

`agent-sync` makes `~/Projects/agent` and `~/Projects/manager` behave as one
versioned configuration source without symlinking incompatible runtime configs.

## Behavior

There is no background job. Configuration changes reach a Mac when you pull:

- `git pull` (or a rebase) in `~/Projects/agent` or `~/Projects/manager` runs
  the managed `post-merge`/`post-rewrite` hook, which reconciles the checked-out
  instructions, skills, MCP policy and runtime settings at once. Hooks
  preserve Git's exit status.
- `bin/agent-sync` does the pull and the reconcile together:
  1. Acquire a single-machine lock.
  2. Fetch both repositories.
  3. Preflight both before changing either one.
  4. Fast-forward only clean default branches with no local commits.
  5. Re-run the machine's stored setup policy.
  6. Verify instructions, skills, MCPs, settings, hooks, and doctor.
  7. Record a credential-free result in
     `~/.local/state/agent-sync/last-run.json`.

  If either repository is dirty, on another branch, ahead, or diverged,
  neither is merged and the blocker is printed.

The scheduled LaunchAgent `com.edihasaj.agent-sync` (every 30 minutes) was
retired on 2026-10-05. Setup removes it from any Mac that still has it.

## Commands

```bash
~/Projects/agent/bin/agent-sync                    # pull both repos and reconcile
~/Projects/agent/bin/agent-sync --reconcile-only   # reconcile what is checked out
~/Projects/agent/bin/agent-sync --check            # report the last run
~/Projects/agent/bin/agent doctor
cat ~/.local/state/agent-sync/last-run.json
```

## Private instruction overlays

The user-level instruction files (`~/AGENTS.md`, `~/.claude/CLAUDE.md`,
`~/.codex/AGENTS.md`, `~/.copilot/copilot-instructions.md`, ...) are symlinks
to the public `AGENTS.MD`. Copilot CLI and the VS Code agent host read
`~/.copilot/copilot-instructions.md` (or `$COPILOT_HOME`); `~/.github/` is only a
repository path and is not read from `$HOME`. Rules that
depend on private tooling do not belong in that public file. Put them in
`manager/instructions/<name>.md` instead, and gate each file with a first line:

```markdown
<!-- requires: mission-work -->
## Repository work claims
- ...
```

`sync-agent-instructions.sh` appends an overlay only on machines where every
listed command resolves with `command -v`. When at least one overlay applies,
the destination becomes a generated regular file (marker line, canonical text,
then each overlay under an `<!-- overlay: name.md -->` comment). When none
apply, the symlink is restored. `--check` fails on a stale render; the
post-merge hook and the scheduled sync re-render after either repository
updates. `--public-only` skips overlays. Preserved pointer files are left alone.

Verify on a machine: `grep -c '<!-- overlay:' ~/.claude/CLAUDE.md`.

## Adding an MCP later

Add one credential-free entry to `manager/configs/mcps.json`, commit, and push.
Both Macs fetch it automatically. `global` entries are rendered into each
selected runtime; `on-demand` and `workflow` entries are removed from user-global
configuration; `external` entries remain owned by their installer.

Secrets and OAuth caches stay machine-local. A manifest may reference an
environment variable name but never its value.
