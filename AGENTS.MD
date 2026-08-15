# AGENTS.MD

Shared operating rules for Edi's coding agents. Keep this file compact: durable
behavior only; project-specific guidance belongs in each repository.

## Start

- Begin repository work with `git status --short --branch`.
- Read the repository's `AGENTS.md` or equivalent and the relevant docs before
  editing.
- Prefer `rg` and `rg --files` for discovery.
- State assumptions when they affect scope or behavior.

## Workspace

- Repositories live under `~/Projects`.
- Public reusable agent tooling belongs in `~/Projects/agent`.
- Private operations, credentials guidance, and organization-specific runbooks
  belong in `~/Projects/manager`.
- Third-party repositories belong under `~/Projects/oss`.
- Put generated artifacts in the active project or a temporary directory, not
  loose across the workspace.

## Changes

- Fix root causes and keep changes focused.
- Preserve user edits and unrelated dirty files.
- Keep source files reasonably small; split them when structure improves.
- Update documentation when behavior or setup changes.
- Add regression coverage for bugs when practical.
- Reuse the project's package manager and established patterns.

## Safety

- Prefer read-only inspection before mutation.
- Use `trash` for file removal so recovery remains possible.
- Never run broad destructive commands against a home, workspace, or repository
  root.
- Do not rewrite Git history, force-push, publish, deploy, or send messages
  without explicit authorization.
- Never commit credentials, tokens, private endpoints, or machine-local state.

## Git

- Review `git status` and the relevant diff before committing.
- Use Conventional Commit subjects.
- Commit only files belonging to the task.
- Push only when requested.
- Prefer HTTPS remotes for repositories under `~/Projects`.
- Do not amend, switch branches, or discard changes unless requested or clearly
  required by the stated workflow.

## Verification

- Run the smallest useful check while iterating, then the repository's full gate
  before handoff.
- For long-running work, keep progress observable and report blockers with the
  exact failing command or error.
- For GitHub pull requests and CI, use `gh` rather than scraping web pages.

## Local tooling

- Browser automation: use `abx` first. Install its browser runtime with
  `abx install-browser` when needed.
- Screenshots and UI inspection: use `shotport` first.
- macOS UI interaction: use `guiport`.
- End-to-end app checks: use `probeport`.
- Cross-platform command smoke tests: use `vmlab` when available.
- Full catalog: `~/Projects/agent/tools.md`.

## Secrets

- Check existing machine-local environment configuration before requesting a
  credential.
- If a secret manager is required, retrieve only the exact field needed and keep
  output redacted.
- Never list vaults, accounts, or secrets broadly.

## Platform notes

- TypeScript: follow the repository runtime and lockfile.
- Python: prefer `uv`; add types to changed code and run the configured checks.
- Swift: preserve signing identity and bundle identifiers; never re-sign an app
  as a debugging shortcut.

## Communication

- Lead with the result.
- Keep progress updates short and concrete.
- If authorization or a choice would materially change scope, stop and ask.
