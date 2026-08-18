# Changelog

## 2026-08-18

- Setup now pins the agent CLI settings this repo owns and checks them for
  drift: `includeCoAuthoredBy=false` in `~/.claude/settings.json`, so no machine
  lands commits co-authored by a model. Unmanaged keys are preserved
  (`scripts/sync-agent-settings.mjs`, wired into POSIX and Windows setup and
  into `agent doctor`).

## 2026-08-15

- Rebuilt the public repository from owned sources and removed imported files.
- Consolidated standalone helpers, removed the extracted browser snapshot, and
  deleted third-party CodexBar, Sparkle, and release artifacts.
- Added standalone, cross-platform `abx` installation to agent setup.
- Published the reusable Sentry CLI and workstation operations skills while
  keeping private, account-specific workflows out of the public repository.
- Installed the bundled `committer` helper under `~/.local/bin` during macOS and
  Linux setup, with drift checks and user-owned-file protection.
- Kept private skills and organization-specific configuration in the sibling
  manager repository.
- Removed the duplicate public MCP manifest; setup now manages only the private
  registrations declared by the manager repository.
- Retired the Chrome DevTools MCP profile in favor of the standalone `abx`
  browser workflow.
