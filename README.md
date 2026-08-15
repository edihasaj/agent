# agent

Portable setup for Edi's coding-agent command line tools. This repository is
public and contains only reusable instructions, installers, MCP registration,
and broadly useful skills. Private operations stay in the sibling `manager`
repository.

## Quick start

macOS:

```bash
./scripts/setup-macos.sh
```

Linux:

```bash
./scripts/setup-linux.sh
```

Windows PowerShell:

```powershell
.\scripts\setup-windows.ps1
```

Setup detects installed agent CLIs, links `AGENTS.MD`, registers public skills,
and reconciles managed MCP entries. The macOS and Linux entry points also
install `abx` when needed and link `scripts/committer` into
`~/.local/bin/committer`. Re-running setup is safe; use `--check` to report drift
without changing machine state.

## Layout

- `AGENTS.MD` — shared working rules
- `bin/` — stable command entry points
- `configs/` — public declarative configuration
- `docs/` — focused setup and runtime notes
- `scripts/` — setup, synchronization, and maintenance
- `skills/` — public, owned skills
- `test/` — setup regression tests

Private skills and MCP configuration may be overlaid from
`../manager/skills` and `../manager/configs/mcps.json`. Use `--public-only` to
exclude that overlay.

## Checks

```bash
./scripts/test-agent-setup.sh
./scripts/setup-macos.sh --check
./bin/agent doctor
```

See `docs/mcp-profiles.md` for MCP behavior and `docs/windows.md` for Windows
setup details.
