---
summary: 'Qwen implementation with Codex and Claude orchestrators, independent verification, and bounded fallbacks.'
read_when:
  - Configuring Codex or Claude model roles and coding fallbacks.
  - Delegating implementation or coordinating independent verification.
  - Checking retired tmux agent instructions.
---

# Agent roles

Qwen does the legwork: research, context gathering, and routine implementation.
It brings concise, evidenced findings back; the larger hosted models judge them,
ask for more context when needed, make the decisions, and review independently.

| Responsibility | Codex | Claude Code |
| --- | --- | --- |
| Orchestration and largest tasks | Astra | Fable |
| Independent verification | Sol (Opus when ChatGPT is at its limit) | Opus 5.5 |
| Research, context and routine implementation | Qwen (`implementer`, `tester`) | Qwen through the local Codex worker |
| Coding fallback | Sonnet (`fallback_implementer`) in gateway chats; Terra in native chats | Sonnet |
| Parallel coding on another provider | Terra (`other_implementer`) | — |

In Claude Code, Opus 5.5 also handles the largest-task fallback.

Codex roles: `orchestrator`, `implementer`, `tester`, `fallback_implementer`,
`other_implementer`, and `verifier`. Machine-specific provider configuration and
canonical role files live in `manager/configs/`; their runbooks live in
`manager/docs/`. Keep credentials in existing machine-local credential storage.
Keep the parent on its orchestration model when invoking an implementation worker.

Claude Code's current reusable roles and model routing are documented in
`~/Projects/manager/docs/claude-agents.md`. Do not override those defaults with
the historical Haiku launch recipe.

## Delegation workflow

Use the active runtime's native delegation when authorized by Edi's request or
applicable repository instructions. Delegation does not require a separate
terminal, an account switch, or a tmux farm.

1. The orchestrator writes a bounded specification, acceptance checks, and file
   ownership for each coding task, or a question, where to look, and the
   evidence wanted for each research task.
2. The implementer answers with evidence, or changes the assigned files, runs
   suitable checks, fixes failures, and returns the actual results. The
   orchestrator judges whether more context is needed.
3. A fresh verifier inspects the implementation against the specification and
   reports actionable defects or the available validation evidence.
4. The orchestrator sends concrete defects back for correction and repeats
   verification until significant defects are resolved.

Keep Qwen on tasks it can complete. Use the hosted implementation fallback only
when the endpoint is unavailable or a focused correction cannot resolve a
blocker. Automatic delegation and task-based fallback are instruction policies;
they do not guarantee that every task follows a fixed state machine.

Keep independent tasks parallel. Start agents with a fresh task when their model
or provider differs. Pass the specification and necessary evidence without
unrelated parent history. Parallel workers must own different files. Workers
should not delegate further unless the orchestrator explicitly assigns that
responsibility.

## Runtime differences

How Qwen is reached depends on the parent chat's provider:

| Parent chat | Qwen route | Sidebar |
| --- | --- | --- |
| Harness Gateway chat (`subscription_gateway`) | `implementer` or `tester` role, or `spawn_agent` with model `qwen/qwen3.8-flash-next` | Yes |
| Native ChatGPT chat | The main thread runs the separate `spark-implementer` profile process | No |

In a gateway chat, `implementer`, `tester`, `fallback_implementer` (Sonnet) and
`other_implementer` (Terra on the gateway's Codex account) omit `model_provider`,
so each child inherits the gateway provider. This was verified on 22 October
2026: an Opus parent started a Qwen role child, and its second Qwen request
reused 67,200 of 70,303 prompt tokens from the cache. A native ChatGPT chat
cannot reach the `qwen/`, `claude/` or `codex/` aliases, and a role that pins a
local provider still fails there. In a native chat, run Qwen through the CLI
profile below and start a coding fallback with model `gpt-5.6-terra`. Gateway
prerequisites and diagnostics are in `manager/docs/codex-agents.md`.

Open a new chat after changing roles; a running chat keeps the role list it
started with. The verifier's instructions prohibit edits. Check the actual
permission mode because live parent overrides can supersede a role's sandbox
default.

If native local-provider delegation is unavailable, use the existing local
Codex worker with a bounded task. Claude Code's hosted implementer uses the
same profile:

```sh
codex exec -p spark-implementer -C /path/to/repository 'Implement the assigned task and report validation.'
```

This keeps inference for the coding work on Qwen while the Claude parent keeps
its hosted model. Claude's Sonnet implementation fallback performs coding
directly when the orchestrator explicitly selects that fallback.

## Ordinary CLI sessions

Start `claude` or `codex` directly in the repository. Their normal profiles,
permissions, hooks and authentication remain in effect. Keep prompts explicit
about the files and result needed.

Follow `AGENTS.MD`'s Flow & Runtime rules for background jobs and persistent
terminals; see `tools.md` for command usage. Do not recreate the farm grid,
inject agent prompts into old panes, or automatically resume retired agent
sessions.

## Retired automation

The former `scripts/agent-send.ts` and `scripts/ralph.ts` recipes are not available
in this repository. Their tmux prompt injection, supervisor loop and forced
model switching are not part of the current setup. Historical conversations
and protected retirement backups remain recoverable.
