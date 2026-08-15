---
summary: "Install and verify the shared agent configuration on Windows."
read_when:
  - Setting up a Windows workstation or VM.
  - Debugging Windows instruction, skill, or MCP synchronization.
---

# Windows setup

Run PowerShell from the repository root:

```powershell
.\scripts\setup-windows.ps1
```

The script detects supported agent CLIs, installs `abx` when missing, links the
shared instructions, registers skills, and reconciles managed MCP entries. It
does not install the agent CLIs themselves.

Useful modes:

```powershell
.\scripts\setup-windows.ps1 -Check
.\scripts\setup-windows.ps1 -PublicOnly
.\scripts\setup-windows.ps1 -AllClis
```

`-Check` reports drift without changing files. `-PublicOnly` excludes the
optional sibling manager overlay. Re-run the normal setup after changing
`AGENTS.MD`, public skills, or `configs/mcps.json`.

Requirements: PowerShell, Git, and Node.js. The `abx` installer selects the
supported Windows package for the current architecture.
