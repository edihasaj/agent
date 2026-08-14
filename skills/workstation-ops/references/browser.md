# Browser operations

Use `abx` first for navigation, inspection, interaction, scraping, and local
web testing—even when Browser, Chrome, DevTools, or Playwright tools exist.

```bash
abx --help
```

On a new machine, run `abx install-browser` if Chromium is missing. If `abx`
fails, quote the exact error and retry once with the correct mode. Fall back
only after a verified limitation: Chrome DevTools, then
`browser-playwright-fallback`.

When the user explicitly requests a live/production Chrome session, use the
dedicated profile:

```bash
~/Projects/abx/scripts/chrome-agent start
ABX_LIVE_CDP_URL=http://127.0.0.1:9223 abx live <command>
```

Use `~/Projects/abx/scripts/chrome-debug` only with explicit approval because
it relaunches personal Chrome.
