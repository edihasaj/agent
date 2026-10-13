---
summary: 'Native agent delegation and optional persistent terminal sessions, without the retired farm automation.'
read_when:
  - Coordinating authorized subagents or checking retired tmux agent instructions.
---

# Agent delegation

Use the active runtime's native delegation when Edi explicitly requests parallel
agent work. Give each worker a bounded task and a disjoint write scope. Delegation
does not require a separate terminal, an account switch, or a tmux farm.

Claude Code's current reusable roles and model routing are documented in
`~/Projects/manager/docs/claude-agents.md`. Do not override those defaults with
the historical Haiku launch recipe.

## Ordinary CLI sessions

Start `claude` or `codex` directly in the repository. Their normal profiles,
permissions, hooks and authentication remain in effect. Keep prompts explicit
about the files and result needed.

Use the active agent's background-job support for builds and other long jobs.
Use ordinary tmux only when persistence or interaction is needed, such as a
debugger or server. Do not recreate the farm grid, inject agent prompts into old
panes, or automatically resume retired agent sessions.

## Retired automation

The former `scripts/agent-send.ts` and `scripts/ralph.ts` recipes are not available
in this repository. Their tmux prompt injection, supervisor loop and forced
model switching are not part of the current setup. Historical conversations
and protected retirement backups remain recoverable.
