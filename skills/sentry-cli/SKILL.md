---
name: sentry-cli
description: Use the Sentry CLI to inspect or manage Sentry organizations, projects, issues, events, traces, logs, releases, alerts, dashboards, artifacts, replays, feedback, monitors, and local Spotlight development. Trigger for Sentry CLI authentication, API exploration, or command troubleshooting.
---

# Sentry CLI

Use `sentry` before raw API calls. Let it auto-detect organization and project
from local configuration; add an explicit target only when detection fails or
selects the wrong target.

## Operating rules

- Run the requested command first. Do not pre-authenticate unless the CLI
  reports an authentication problem.
- Prefer dedicated commands such as `sentry issue view` over `sentry api`.
- Use `sentry schema` to discover endpoints and `sentry api` only for uncovered
  operations.
- Use `--json --fields ...` and `--limit` to constrain agent-facing output.
- Confirm before destructive operations such as project/release deletion or
  starting a product trial.
- Verify the resolved organization/project before mutations.
- Never print, log, or persist authentication tokens.

Exit-code routing:

| Range | Meaning | Response |
| --- | --- | --- |
| 0 | Success | Continue |
| 10–19 | Authentication | Ask for `sentry auth login` |
| 20–29 | Input | Correct arguments |
| 30–39 | API | Retry or report |
| 40–49 | Unavailable feature | Explain plan/settings constraint |
| 50–69 | Operation/command | Report stderr |

## Common workflows

### Investigate an issue

```bash
sentry issue list --query "is:unresolved" --limit 5
sentry issue view PROJECT-123
sentry issue explain PROJECT-123
sentry issue plan PROJECT-123
```

Use the short issue ID (`PROJECT-123`), not the numeric group ID.

### Inspect traces and logs

```bash
sentry trace list --limit 5
sentry trace view <trace-id>
sentry span list <trace-id>
sentry trace logs <trace-id>
sentry log list --follow
```

Use `--period 1h`, `24h`, or `7d` to constrain time.

### Run local Spotlight

```bash
sentry local run -- npm run dev
sentry local -f ai
```

Without a DSN, events remain local. With a DSN, the SDK may send to both local
Spotlight and the configured Sentry organization.

### Manage a release

```bash
sentry release create my-org/1.0.0 --project my-project
sentry release set-commits my-org/1.0.0 --auto
sentry release finalize my-org/1.0.0
sentry release deploy my-org/1.0.0 production
```

The positional is `<org-slug>/<version>`; the version must exactly match the
SDK's `release` value. `--auto` needs a full local Git checkout and repository
integration. Use `--local` when integration is unavailable.

### Explore the API

```bash
sentry schema
sentry schema issues
sentry api /api/0/organizations/my-org/
```

## Reference routing

Read only the references needed for the task.

- Account and discovery: [auth](references/auth.md), [CLI settings](references/cli.md),
  [info](references/info.md), [schema](references/schema.md), [API](references/api.md).
- Ownership: [organizations](references/org.md), [projects](references/project.md),
  [teams](references/team.md), [repositories](references/repo.md),
  [product trials](references/trial.md).
- Errors and users: [issues](references/issue.md), [events](references/event.md),
  [alerts](references/alert.md), [feedback](references/feedback.md),
  [conversations](references/conversation.md), [replays](references/replay.md).
- Telemetry: [traces](references/trace.md), [spans](references/span.md),
  [logs](references/log.md), [Explore](references/explore.md),
  [monitors](references/monitor.md), [dashboards](references/dashboard.md).
- Releases and artifacts: [releases](references/release.md),
  [sourcemaps](references/sourcemap.md), [debug files](references/debug-files.md),
  [code mappings](references/code-mappings.md), [builds](references/build.md),
  [snapshots](references/snapshots.md).
- Mobile symbols: [ProGuard](references/proguard.md),
  [Dart symbol maps](references/dart-symbol-map.md),
  [React Native](references/react-native.md).
- Local setup: [local Spotlight](references/local.md), [project init](references/init.md).

## Common mistakes

- Parsing formatted output: add `--json`.
- Supplying organization/project unnecessarily: try auto-detection first.
- Using free text in `--query`: use Sentry search syntax such as
  `is:unresolved` or `assigned:me`.
- Downloading API schemas: use `sentry schema`.
- Running `set-commits --auto` without `actions/checkout` and full history.
- Double-prefixing a release version: `sentry/1.0.0` means organization
  `sentry`, version `1.0.0`.

Run `sentry <noun> <verb> --help` when a reference lacks a current flag.
