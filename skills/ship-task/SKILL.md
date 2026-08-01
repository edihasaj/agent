---
name: ship-task
description: >-
  End-to-end task pipeline for a managed repo. Given a repo key and a task
  reference (Jira key, GitHub issue, URL, or free text), it resolves the task,
  creates a branch in the repo's convention, implements the change, runs the
  repo's gates (lint/typecheck/test), runs security + code review passes,
  writes a PR description, optionally smoke-tests, and stops PR-ready or opens
  a PR per the repo's config. Use when the user says "ship REPO TASK",
  "/ship-task ...", or points the agent at a Jira/GitHub task to implement.
---

# ship-task — point-and-ship pipeline

Run a per-task pipeline so the human stops doing the manual loop (copy task →
prompt → branch → implement → lint/test → write PR → review again → "done?").
Do the whole thing; stop only where the repo config says to. Telegraph each
stage in short lines.

## Inputs

`$ARGUMENTS` = `<repo> <task-ref> [notes…]`
- `<repo>` — a config key. Configs live in the shipyard config home: run
  `shipyard where` to find it (typically `~/.config/shipyard/repos/<repo>.yml`,
  or `$SHIPYARD_HOME/repos/`, or `./.shipyard/repos/`).
- `<task-ref>` — any of:
  - Jira key — `ABC-123`
  - Jira URL — `…/browse/ABC-123`, or any URL with `selectedIssue=ABC-123`
  - GitHub issue/PR shorthand — `#86`
  - GitHub URL — `https://github.com/<owner>/<repo>/issues/86` or `/pull/86`
  - free text — `"add retry backoff to webhooks"`
- `notes…` — optional extra instructions; weave them in.

A pasted URL may arrive as the FIRST token (repo omitted): for a GitHub URL,
infer `<repo>` by matching `<owner>/<repo>` against each config's `github.repo`;
for a Jira URL, match the project-key prefix against `jira.project_key`. If
ambiguous, STOP and ask. If still unresolved, infer from CWD (match `path:`);
if nothing matches, STOP and ask, and offer to scaffold one (`shipyard init`).

## Step 0 — Load config (always first)

Read the repo's config YAML. It defines: `path`, `task_source`, `ticket`,
`base_branch`, `branch_format`, `branch_types`, `commit_convention`,
`worktree`, `gates`, `review`, `pr`, `push`, `test_strategy`, `vmlab`, `notes`.
Everything below is parameterized by it.

Default to `cd` into `path`. If the input notes include
`SHIPYARD_WORKTREE_PATH=<path>`, that path was created by the shipyard launcher;
use it as the working directory instead of `path`, and do not create another
worktree. If `worktree.enabled: true` but no launcher-provided path is present,
create a detached worktree yourself under `worktree.root` from `base_branch`
before editing, then use that worktree for the rest of the run.

Run `git status --short --branch`; if dirty and not on the base branch or a
shipyard-created worktree, STOP and ask.

## Step 1 — Resolve the task

- Normalize `<task-ref>`: if a URL, extract the identifier — Jira `[A-Z]+-\d+`
  from `/browse/…` or `selectedIssue=…`; GitHub number from `/issues/<n>` or
  `/pull/<n>`. A `/pull/<n>` means work an existing PR, not open a new one —
  note that and ask if unclear.
- `task_source: jira` → use the Atlassian/Jira integration (MCP if present) to
  fetch summary, description, acceptance criteria, type, parent. If it's not
  connected, say so and fall back to the pasted text.
- `task_source: github` → `gh issue view <ref> --json title,body,labels,number`
  (or `gh pr view <n>`). `<ref>` accepts a number or full URL.
- free text / none → use the text as the spec; generate a slug.

Restate the task in 2–3 lines: what + acceptance criteria + type
(feature/bug/chore). This drives branch type and commit type.

### Drafting or updating a ticket body

When the task is to **create or update a ticket's description** (a thin task
that needs fleshing out, or normalizing an existing one) rather than implement
code, source the skeleton from `ticket.template` — resolved exactly like
`pr.template` (see Step 8: `""` → built-in default; filesystem path; or Obsidian
URL). Preserve the template's structure verbatim and fill only the prose
placeholders and obvious tokens from the resolved task. Write the body to the
ticket via the task source (Jira/GitHub integration), and echo it back.

**Confirm the write persisted.** The Jira/GitHub edit APIs publish immediately —
there is no separate save step — but always re-fetch the issue after writing and
confirm the fields hold the new content before reporting done. Note for the
user: if they had the issue open in the Jira editor while the API wrote, the
browser keeps a local draft and shows "unsaved changes"; that is a stale
client-side draft to **discard/refresh**, not a failed save — the server already
has the published version.

Keep section headings small (`###`, not `##`) so the ticket body doesn't shout.

You may also update the **title/summary** in the same edit — it's a plain-text
field (no ADF). When a spike concludes, drop the `Spike - ` prefix and retitle
to the implementation outcome (e.g. _"Run parallel test harness as per-case
NUnit tests"_).

**Acceptance criteria go in their own fields, not the description.** If the
tracker exposes dedicated acceptance-criteria fields, write the criteria there
and leave them out of the description body:

- Discover field ids from the issue metadata (Jira: `getJiraIssue` with
  `expand=names`, or editmeta). Match by display name — e.g. _End User
  Acceptance Criteria_ and _PR Acceptance Criteria_, or a generic _Acceptance
  Criteria_.
- Rich-text custom fields take **ADF**, not markdown — send the value as an
  Atlassian Document (a `doc` with a `bulletList`), in a separate update from
  the markdown `description` (one editJiraIssue call can't mix formats).
- Only if no such field exists, fall back to appending the criteria as
  description sections.

The built-in default (when `ticket.template` is `""`) — description body:

- **Status** — _optional: readiness + any blocking dependency (PR/commit/ticket); delete if N/A._
- **Ask** — _one paragraph: the outcome this ticket delivers._
- **Description** — _**Background** (domain/data/constraint); **Already in place — do not redo** (what existing code/spikes deliver, with file/line pointers); **Remaining scope** (concrete named work items, each with where it lives + the check that proves it)._
- **Out of scope** — _what this ticket explicitly does not cover._

…plus, into their dedicated tracker fields: **End-user acceptance criteria**
(observable behaviour, no implementation detail) and **PR acceptance criteria**
(verifiable deliverables — tests, docs, behaviour — the PR must show).

## Step 2 — Plan (read before write)

- Read repo `CLAUDE.md`/`AGENTS.md`/contributor docs if present; follow them.
- Locate the files to touch (search, don't guess). List them.
- Note the gate commands from config so you know how you'll verify.
Keep the plan to a short bullet list. Proceed unless the task is ambiguous.

## Step 3 — Branch

- `git fetch`; branch FROM a fresh `base_branch` (pull latest first).
- If running inside a shipyard-created worktree, treat that worktree as already
  positioned at the fresh base; create the task branch inside the worktree.
- Name via `branch_format`, substituting `{type}` (per `branch_types`),
  `{key}` (task id, omitted if none), `{slug}` (kebab-case summary, ~6 words).
  Match the config's `branch_examples` exactly. Confirm the name, then create.

## Step 4 — Implement

Match surrounding code (naming, comment density, idiom). Follow repo
conventions. Add a regression test for bugs when it fits. Keep files small;
split if needed. Small reviewable commits using `commit_convention`.

**Respect git hooks — never `--no-verify`.** If the repo has husky/pre-commit
hooks (formatters, lint-staged, commit-msg rules), let them run; they encode
the team's rules. If a hook needs a toolchain (e.g. `dotnet tool restore`,
`npm ci`), that belongs in `gates.install` — run it before the first commit.
If a hook fails, fix the cause; don't bypass.

## Step 5 — Self-gate

Run `gates.install` (if needed) then `gates.lint`, `gates.typecheck`,
`gates.test`. Fix failures and re-run until green. For heavy gates (full e2e),
run `gates.test_scoped` or explicitly note the skip — no silent skips. Report
pass/fail with actual output on failure.

## Step 6 — Security review

Run a security review over the diff (`/security-review` if available). Triage;
fix real findings. Always run it, even for small diffs. Summarize: N findings,
M fixed, rest with rationale.

## Step 7 — Code review pass 2 (adversarial)

Run a code review at the effort in `review.level` (default `high`) over the
diff. Be a hostile reviewer: correctness, edge cases, reuse/simplification.
Apply fixes. Re-run gates if you changed logic.

## Step 8 — PR description

Write to `/tmp/<key-or-slug>-pr.md`. Source the skeleton from `pr.template`:

- **Unset (`""`)** → use the default **Summary / Changes / Testing / Risk /
  Linked task** and match how the team writes PRs here
  (`gh pr list --state merged --limit 3` + `gh pr view`).
- **Filesystem path** (expand a leading `~`) → read that file.
- **Obsidian URL** — `obsidian://open?vault=<v>&file=<note>` → read it with
  `obsidian read path="<note>.md" vault=<v>` (note may include subfolders;
  append `.md` if absent). If the `obsidian` CLI is missing, fall back to the
  vault file path; if still unresolved, STOP and say so — don't silently use
  the default.

When a template is provided, **preserve its structure verbatim** — keep every
header, comment, and checklist line as-is — and only fill in the prose
placeholders (the `_italic prompts_`) and obvious tokens (e.g. `<TICKET-ID>`)
from the resolved task. Leave checkboxes unchecked for the human. Always
include the task link.

**Always write the filled body to the file** — a configured `pr.template` is a
skeleton to fill, never a reason to skip writing the description. Whoever opens
the PR (the agent on `push: pr`, or the human on `push: manual`) takes the body
from `/tmp/<key-or-slug>-pr.md`, so the PR must never be opened without it.

## Step 9 — Local test (optional, per config)

If `vmlab.enabled: true`, run the configured vmlab smoke and capture evidence:

- `vmlab.flow` set → `vmlab run <target> <flow>`
- `vmlab.command` set → `vmlab run <target> -- <command>`
- `vmlab.web` set → `vmlab web <target> -- <web args>`
- `vmlab.gui` set → `vmlab gui <target> -- <gui args>`

Use `vmlab.target` as a target name or selector. Record the evidence bundle id
or path when `vmlab.evidence` is true. If vmlab or the target is unavailable,
report the exact failure and continue unless the repo config or task explicitly
made this smoke mandatory.

If `vmlab.enabled` is false but `test_strategy` is set, do the described real
smoke and capture evidence (screenshot/log). Never let optional local smoke
silently disappear: either capture proof or say what was unavailable. Step 5
gates remain the correctness gate. Don't invent flows that don't exist — offer
to create one instead.

## Step 10 — Done gate + handoff

Self-check: does the diff satisfy the acceptance criteria? Anything unverified?
Then act on `push`:
- `push: manual` (enterprise) → **do NOT push or open a PR.** Output: branch
  name, one-paragraph summary, gate results, security/review summary, PR-body
  path, open questions. The human reviews and pushes.
- `push: pr` → push branch, then open the PR **passing the Step 8 body file
  explicitly**: `gh pr create --base <pr.base> --title "<key>: <summary>"
  --body-file /tmp/<key-or-slug>-pr.md` (add `--draft` if `pr.draft`). **Never
  run `gh pr create` without `--body-file`** — omitting it drops the
  description/template entirely. Print the PR URL.
- `push: ask` → present the summary, then ask before pushing.

Final message = a tight status block, not prose. Leave a breadcrumb of any
assumptions made.

## Guardrails

- Never force-push, `reset --hard`, or touch other branches.
- Never delete a shipyard-created worktree automatically; leave its path in the
  handoff so the human/farm scheduler can inspect or clean it.
- Never auto-push repos with `push: manual`.
- If blocked (missing creds, ambiguous task, unfixable gate), STOP with a
  short list of what's missing — don't band-aid.
- Respect the repo's own `CLAUDE.md`/`AGENTS.md` over these defaults.
