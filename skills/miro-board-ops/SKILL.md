---
name: miro-board-ops
description: Inspect and modify Miro boards through the REST API when the hosted Miro MCP cannot move or delete items. Use for listing or reading board items, moving items, deleting items, or deleting a board from a Miro URL or ID.
---

# Miro Board Operations

Use the bundled CLI from the user's current directory:

```bash
node ~/.agents/skills/miro-board-ops/scripts/miro --help
```

Set `MIRO_TOKEN` in the process environment. It needs `boards:read` for reads and
`boards:write` for mutations. Never print or commit the token.

## Workflow

1. Run `whoami` to verify authentication when needed.
2. Run `list <board>` or `get <board> <item>` to resolve exact targets.
3. Use `move` or `delete` only when the user explicitly requests that mutation.
4. Use `board-delete` only for an explicitly named board and pass `--yes` after
   confirming its ID. If the target is ambiguous, stop and ask.

The board argument can be a full Miro board URL or a bare board ID. Item
arguments can be bare IDs or URLs containing `moveToWidget=<id>`.

```bash
node ~/.agents/skills/miro-board-ops/scripts/miro list <board> --type data_table_format
node ~/.agents/skills/miro-board-ops/scripts/miro get <board> <item>
node ~/.agents/skills/miro-board-ops/scripts/miro move <board> <item> --x 100 --y 200
node ~/.agents/skills/miro-board-ops/scripts/miro delete <board> <item> [<item>...]
node ~/.agents/skills/miro-board-ops/scripts/miro board-delete <board> --yes
```

MCP-created tables use REST type `data_table_format`; the generic item endpoints
support reading, moving, and deleting them.
