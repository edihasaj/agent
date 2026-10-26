---
summary: 'Qwen-first search, research, implementation and testing, with cloud decisions, independent verification and evidenced fallbacks.'
read_when:
  - Configuring Codex or Claude model roles and coding fallbacks.
  - Delegating implementation or coordinating independent verification.
  - Checking retired tmux agent instructions.
---

# Agent roles

These roles are optional. Use the workflow below when they are configured;
otherwise implement, test and review directly. Do not install roles or providers
just to satisfy this guide.

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

When configured, delegate bounded legwork to Qwen by default. Use it for
web and documentation searches, code exploration, log and configuration analysis,
inventories, comparisons, summaries, context gathering, routine coding and test
work. Keep credentials out of worker prompts and reports; existing permissions
and authorization for sensitive actions still apply. The main model defines the
question and makes decisions from the returned evidence. Tiny known commands can
stay in the main thread when delegation would add more overhead than the work.

Use the active runtime's native delegation. A handoff does not require a
separate terminal, an account switch, or a tmux farm. Prefer one bounded research
worker that returns paths, sources, findings and uncertainties over cloud agents
performing broad searches or repeating the worker's reads.

1. The orchestrator writes a bounded specification, acceptance checks, and file
   ownership for each coding task, or a question, where to look, and the
   evidence wanted for each research task.
2. The implementer sends an early finding or blocker, then answers with evidence,
   or changes the assigned files, runs
   suitable checks, fixes failures, and returns the actual results. The
   orchestrator judges whether more context is needed.
3. Use a fresh verifier when configured; otherwise review the implementation
   directly against the specification and validation evidence.
4. The orchestrator sends concrete defects back for correction and repeats
   verification until significant defects are resolved.

Keep Qwen on tasks it can complete. Use the hosted implementation fallback only
when the endpoint is unavailable, an evidenced blocker or stalled task prevents
progress, or a focused correction cannot resolve a defect. State the actual
reason and preserve valid work. `pending_init`, silence alone, and an unchanged
diff during research do not establish failure. Check recent model/tool activity
and ask for a bounded progress report before interrupting; let progressing work
finish. Use bounded waits rather than duplicate workers or indefinite retries.
Explicit cancellation and changed scope still permit stopping a worker.
Automatic delegation and task-based fallback are instruction policies;
they do not guarantee that every task follows a fixed state machine.

Keep independent tasks parallel. In Codex, start named workers with
`fork_turns="none"`: a full-history fork inherits the parent's model instead of
the role's model. Do not launch an orchestrator child or a generic/explorer cloud
child for Qwen-suitable legwork. Pass the specification and necessary evidence without
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

In a native Codex chat, use the existing local Codex worker with a bounded task:

```sh
CODEX_HOME="$HOME/.codex" dgx run -- codex --no-daemon exec -p spark-implementer -C /path/to/repository 'Answer the assigned bounded question with evidence, or implement the assigned task and report validation.' </dev/null
```

Claude Code's hosted implementer uses its dedicated private Qwen worker home,
as described in `manager/docs/claude-agents.md`; do not substitute the normal
Codex home for it. Its Sonnet implementation fallback performs coding directly
when the orchestrator explicitly selects that fallback.

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
