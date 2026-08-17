---
summary: "Publish to npm via tmux + 1Password CLI (op)"
read_when:
  - "Need npm publish without copy/paste secrets."
  - "Need npm OTP/TOTP from 1Password."
---

# npm publish via tmux + op

Goal: publish to npm without pasting tokens/passwords into terminal logs.

## Prereqs

- 1Password desktop app unlocked + CLI integration enabled.
- `op` installed.
- `tmux` installed.

## tmux session (required)

Use a persistent tmux session so `op` auth survives across commands.

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
```

Why both `env -u` and `unset`: a login shell may source `~/.profile` and restore the
service-account token after tmux starts. Clearing it inside the pane guarantees that
desktop integration handles subsequent reads.

## Preferred: granular automation token (+ optional OTP)

Store a granular npm token in 1Password (item field `token`), plus TOTP if required.

```bash
TOKEN_REF='op://<Vault>/<Item>/token'
OTP_REF='op://<Vault>/<Item>/one-time password?attribute=otp'

tmux -S "$SOCKET" send-keys -t "$SESSION" -- "NODE_AUTH_TOKEN=\"\$(op read \"$TOKEN_REF\" | tr -d \"\\n\")\" npm publish --otp \"\$(op read \"$OTP_REF\" | tr -d \"\\n\")\"" Enter
```

Notes:
- `tr -d "\n"` avoids accidental extra submits when pasting/reading.
- Avoid printing token/OTP (no `echo`, no `set -x`, no pane capture right after OTP).

## If you’re already logged in: OTP-only publish

If `npm whoami` works, you usually only need OTP for publish:

```bash
OTP_REF='op://<Vault>/<Item>/one-time password?attribute=otp'
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "npm publish --otp \"\$(op read \"$OTP_REF\" | tr -d \"\\n\")\"" Enter
```

Tip: unset CI tokens so you don’t accidentally override your local login:

```bash
env -u NPM_TOKEN -u NODE_AUTH_TOKEN npm whoami
```

## Fallback: `npm login` using op buffers (no echo)

When password auth is unavoidable, avoid typing secrets by piping into tmux buffers and pasting.

```bash
USER_REF='op://<Vault>/<Item>/name'
PASS_REF='op://<Vault>/<Item>/password'
EMAIL_REF='op://<Vault>/<Item>/email'
OTP_REF='op://<Vault>/<Item>/one-time password?attribute=otp'

# load buffers (strip trailing newline)
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "op read \"$USER_REF\"  | tr -d \"\\n\" | tmux -S \"$SOCKET\" load-buffer -b npm_user  -" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "op read \"$PASS_REF\"  | tr -d \"\\n\" | tmux -S \"$SOCKET\" load-buffer -b npm_pass  -" Enter
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "op read \"$EMAIL_REF\" | tr -d \"\\n\" | tmux -S \"$SOCKET\" load-buffer -b npm_email -" Enter

# run login; paste at prompts (repeat pattern for Email/OTP)
tmux -S "$SOCKET" send-keys -t "$SESSION" -- "npm login --auth-type=legacy" Enter
tmux -S "$SOCKET" paste-buffer -t "$SESSION" -b npm_user
tmux -S "$SOCKET" send-keys    -t "$SESSION" -- Enter
tmux -S "$SOCKET" paste-buffer -t "$SESSION" -b npm_pass
tmux -S "$SOCKET" send-keys    -t "$SESSION" -- Enter
```

Gotchas:
- If npm says “Incorrect or missing password”, the 1Password password is stale or the paste didn’t reach the prompt.
- Don’t run `tmux capture-pane` after pasting OTP (it may echo); wait 30–60s if you must debug.
- Repeated reads of the password field can trigger multiple 1Password “password used/copied” alerts; OTP-only flow avoids that entirely.

## Verify

```bash
npm whoami
npm view <pkg> version
```

## Cleanup

```bash
tmux -S "$SOCKET" kill-session -t "$SESSION"
test ! -e "$SOCKET" || trash "$SOCKET"
```
