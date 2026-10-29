---
summary: 'Local-first research, implementation, testing and preliminary review, with cloud decisions and independent final verification.'
read_when:
  - Configuring Codex or Claude model roles and coding fallbacks.
  - Delegating implementation or coordinating independent verification.
  - Checking retired tmux agent instructions.
---

# Agent roles

These roles are optional. Use the workflow below when they are configured;
otherwise implement, test and review directly. Do not install roles or providers
just to satisfy this guide.

The configured local worker does research, context gathering, routine implementation,
and first-pass verification or review. It returns concise evidence and uncertainties;
the main model makes decisions. Larger models handle difficult diagnosis and
independent final review of nontrivial or risky changes.

| Responsibility | Codex | Claude Code |
| --- | --- | --- |
| Orchestration and largest tasks | Astra | Fable |
| First-pass research, checks and review | Fresh Qwen `implementer` or `tester` | Qwen through a fresh `implementer` handoff |
| Independent final review of nontrivial or risky changes | Sol (Opus when ChatGPT is at its limit) | Opus 5.5 |
| Context and routine implementation | Qwen `implementer` | Qwen through the local Codex worker |
| Coding fallback | Sonnet (`fallback_implementer`) in gateway chats; Terra in native chats | Sonnet |
| Parallel coding on another provider | Terra (`other_implementer`) | — |

In Claude Code, Opus 5.5 also handles the largest-task fallback.

Codex roles: `orchestrator`, `implementer`, `tester`, `fallback_implementer`,
`other_implementer`, and `verifier`. Machine-specific provider configuration and
canonical role files live in `manager/configs/`; their runbooks live in
`manager/docs/`. Keep credentials in existing machine-local credential storage.
Keep the parent on its orchestration model when invoking an implementation worker.
Do not classify broken status delivery or an explicit hold as model failure.

Paid OpenRouter fallback uses the DeepSeek V4 Flash family by default. Bigger
tasks use suitable Claude/Codex subscriptions first. DeepSeek Pro and every GLM
variant require both a capability Flash cannot provide and confirmed
unavailability or inability of suitable subscriptions. State both reasons before
selecting that exception. General OpenRouter permission, busy Qwen, parallelism
or a transient tool error does not select those models. Unknown quota is not
proof of unavailability. Preserve explicit user choices and existing worker models.

Claude Code's current reusable roles and model routing are documented in
`~/Projects/manager/docs/claude-agents.md`. Do not override those defaults with
the historical Haiku launch recipe.

## Delegation workflow

When configured, delegate bounded legwork to Qwen by default. Use it for
web and documentation searches, code exploration, log and configuration analysis,
inventories, comparisons, summaries, context gathering, routine coding, test work,
small acceptance checks, failure reproduction and preliminary diff review. Keep credentials out of worker prompts and reports; existing permissions
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
3. Use a fresh local worker for bounded review or verification. Require concrete
   findings with file/line references, failure scenarios and observed checks;
   review-only tasks make no edits. Small, low-risk changes can finish after the
   main model checks that evidence. For nontrivial or risky changes, send the
   specification, diff, local findings and unresolved questions to an independent
   verifier when configured; otherwise perform that final review directly.
4. The orchestrator sends concrete defects back for correction and repeats
   verification until significant defects are resolved.

The author does not approve its own patch. A fresh worker may use the same local
model, but its review needs separate context. A local pass is preliminary evidence,
not a substitute for independent final review where required. Do not add a cloud
reviewer merely to repeat a completed bounded check. Skip the local pass when the
user requests a particular reviewer or local availability blocks progress.

Keep Qwen on tasks it can complete. Use the hosted implementation fallback only
when the endpoint is unavailable, an evidenced blocker or stalled task prevents
progress, or a focused correction cannot resolve a defect. State the actual
reason and preserve valid work. `pending_init`, silence alone, and an unchanged
diff during research do not establish failure. Check recent model/tool activity
and ask for a bounded progress report before interrupting; let progressing work
finish. Use bounded waits rather than duplicate workers or indefinite retries.
An explicit hold, worktree move, dependency wait or read-only assignment is not
an implementation attempt. Pause the task budget while held. Resume explicitly
with the current path, owned files and acceptance check before expecting edits.
An unsupported status/messaging call is a coordination failure, not model
incapability: inspect available activity/history or the final report and address
the transport separately. Do not repeatedly request the broken channel and
escalate because it stays silent. For routine-work escalation, state the bounded
task, authorization/resume state, latest successful activity, exact failing
check/blocker and focused correction. A complex project or extra parallelism
alone does not justify moving every bounded implementation task to cloud models.
Explicit cancellation and changed scope still permit stopping a worker.
Automatic delegation and task-based fallback are instruction policies;
they do not guarantee that every task follows a fixed state machine.

Keep independent tasks parallel. Prefer fresh worker tasks to keep prompts
small; in Codex this is `fork_turns="none"`. Current MultiAgentV2 applies a named
role's model even with a full-history fork. Use shared history when needed.
Do not launch an orchestrator child or a generic/explorer cloud
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
default. Review-only instructions on a shared coding/testing role do not change
its sandbox. Native review workers use `--sandbox read-only`; gateway workers
retain the caller's permission boundary and must follow the no-edit assignment.

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
