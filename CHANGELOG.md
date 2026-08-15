# Changelog

## 2026-08-15

- Rebuilt the public repository from owned sources and removed imported files.
- Added standalone, cross-platform `abx` installation to agent setup.
- Installed the bundled `committer` helper under `~/.local/bin` during macOS and
  Linux setup, with drift checks and user-owned-file protection.
- Kept private skills and organization-specific configuration in the sibling
  manager repository.
- Removed the duplicate public MCP manifest; setup now manages only the private
  registrations declared by the manager repository.
