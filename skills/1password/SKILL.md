---
name: 1password
description: Set up and use 1Password CLI (op). Use when installing the CLI, choosing desktop or lock-independent service-account authentication, enabling desktop app integration, signing in, maintaining a persistent tmux session, or reading/injecting/running targeted secrets via op.
metadata: {"clawdbot":{"emoji":"🔐","requires":{"bins":["op"]},"install":[{"id":"brew","kind":"brew","formula":"1password-cli","bins":["op"],"label":"Install 1Password CLI (brew)"}]}}
---

# 1Password CLI

Follow the official CLI get-started steps. Don't guess install commands.

## References

- `references/get-started.md` (install + app integration + sign-in flow)
- `references/cli-examples.md` (real `op` examples)

## Workflow

1. Check OS + shell.
2. Verify CLI present without invoking it: `command -v op`.
3. Select one authentication mode without printing credentials:
   - If `OP_SERVICE_ACCOUNT_TOKEN` is already set and scoped to the required vault, use
     service-account mode. It works independently of the desktop app lock.
   - Otherwise use desktop-app mode and confirm integration is enabled and the app unlocked.
4. REQUIRED: create a dedicated tmux session for every `op` command. Never call `op`
   directly, including diagnostics.
5. In service-account mode, preserve `OP_SERVICE_ACCOUNT_TOKEN`, do not run `op signin`,
   and verify access inside tmux with redacted output before reading an exact item.
6. In desktop-app mode, unset `OP_SERVICE_ACCOUNT_TOKEN`, `OP_CONNECT_HOST`, and
   `OP_CONNECT_TOKEN` inside tmux before the first `op` command. Sign in and verify the
   same explicit account inside that pane.
7. If multiple desktop accounts exist, use the same explicit `--account` or `OP_ACCOUNT`
   for every read.
8. Prefer an exact item UUID for targeted reads. Do not assume a vault is named `Personal`;
   vault display names vary by account.

## REQUIRED tmux session (T-Max)

The shell tool uses a fresh TTY per command. Always run `op` inside one dedicated tmux
session. Keep custom sockets directly under `/tmp`; macOS Unix-domain sockets have a
short path limit.

### Lock-independent service-account session

Use this only when a scoped token is already configured. Never place the token in a command
argument, tmux command buffer, log, or generated file. A new tmux server inherits it from the
calling shell environment. Reuse the named session when the user explicitly requests
persistent access.

```bash
test -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" || {
  echo "Scoped 1Password service-account token is not configured" >&2
  exit 1
}

umask 077
SOCKET="/tmp/codex-op-service-${UID}.sock"
SESSION="op-service"

if ! tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
  tmux -S "$SOCKET" new -d -s "$SESSION" -n shell
fi

tmux -S "$SOCKET" send-keys -t "$SESSION" -- \
  'op whoami >/dev/null && echo "1Password service account ready"' Enter
```

Verify only the required item before use:

```bash
VAULT='<exact-vault>'
ITEM_ID='<exact-item-uuid>'
tmux -S "$SOCKET" send-keys -t "$SESSION" -- \
  "op item get '$ITEM_ID' --vault '$VAULT' --format json >/dev/null && echo 'Target item ready'" Enter
```

### Desktop-app session

Use a fresh socket and session so inherited service credentials cannot select the wrong auth
mode:

```bash
SOCKET="/tmp/codex-op-${UID}-$$.sock"
SESSION="op-auth-$(date +%Y%m%d-%H%M%S)"
ACCOUNT="my.1password.com"

env -u OP_SERVICE_ACCOUNT_TOKEN -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN \
  tmux -S "$SOCKET" new -d -s "$SESSION" -n shell
tmux -S "$SOCKET" send-keys -t "$SESSION" -- \
  "unset OP_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST OP_CONNECT_TOKEN; export OP_ACCOUNT='$ACCOUNT'" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "op signin --account '$ACCOUNT'" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "op whoami --account '$ACCOUNT'" Enter
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION" -S -200
tmux -S "$SOCKET" kill-session -t "$SESSION"
```

## Guardrails

- Never paste secrets into logs, chat, or code.
- Prefer `op run` / `op inject` over writing secrets to disk.
- Treat "always available" as scoped service-account access, not an unlocked desktop app.
  Desktop lock state does not affect it, but token revocation or permission changes do.
- Do not persist a new service-account token unless the user explicitly authorizes always-on
  machine access. Keep any approved machine-local secret source mode `0600`.
- A persistent tmux server does not survive a reboot. Recreate the session from the approved
  machine-local environment after startup.
- Never mix desktop-app and service-account authentication in one tmux session. For a
  service-account workflow, keep `OP_SERVICE_ACCOUNT_TOKEN` and do not run `op signin`.
- A successful `op signin` does not override an inherited `OP_SERVICE_ACCOUNT_TOKEN`.
- If sign-in without app integration is needed, use `op account add`.
- If a command returns "account is not signed in", re-run `op signin` inside tmux and authorize in the app.
- Do not run `op` outside tmux; stop and ask if tmux is unavailable.
