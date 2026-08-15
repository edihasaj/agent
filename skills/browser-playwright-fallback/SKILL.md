---
name: browser-playwright-fallback
description: Deterministic browser automation via inline Playwright scripts. Use only after abx is unavailable or lacks a required capability, or when a task specifically needs a reproducible raw Playwright flow. No permanent install required.
---

# Browser Playwright Fallback

Fallback layer below `abx`. Use when:

- `abx` is unavailable or has failed after one corrected retry.
- The flow needs raw Playwright APIs that `abx` does not expose, such as custom assertions or multi-page orchestration.
- A checked-in or reproducible browser script is the requested artifact.

Use `abx` for normal navigation, inspection, interaction, scraping, screenshots, and local web testing. Record the exact `abx` limitation before falling back.

## Prereqs

- Node.js (any LTS). `npx` ships with it.
- That's it. `npx playwright` self-installs the browser binaries on first use (~300MB for Chromium alone; ~900MB for the trio). Subsequent runs reuse the cache at `~/Library/Caches/ms-playwright/`.

## Pattern

Inline a single-file script, save to `/tmp/pw-<name>-$(date +%s).mjs`, run it:

```bash
cat > /tmp/pw-smoke.mjs <<'SCRIPT'
import { chromium } from "playwright"
const browser = await chromium.launch({ headless: true })
const context = await browser.newContext()
const page = await context.newPage()
try {
  await page.goto("https://example.com", { waitUntil: "domcontentloaded" })
  const heading = await page.locator("h1").first().textContent()
  console.log(JSON.stringify({ ok: true, heading }))
} catch (error) {
  console.log(JSON.stringify({ ok: false, error: String(error) }))
  process.exitCode = 1
} finally {
  await browser.close()
}
SCRIPT
npx --yes playwright@latest install --with-deps chromium 2>/dev/null || true
node --experimental-vm-modules /tmp/pw-smoke.mjs
```

Log JSON to stdout so the calling agent can `jq` the result. Keep the script idempotent and self-contained so it's easy to re-run by hand.

## Recipes

### Screenshot + save

```js
await page.goto(url, { waitUntil: "networkidle" })
await page.screenshot({ path: "/tmp/pw-shot.png", fullPage: true })
```

### Assert text present

```js
await page.goto(url)
await page.getByText("Sign in").waitFor({ state: "visible", timeout: 5000 })
```

### Fill a form + submit

```js
await page.goto(url)
await page.getByLabel("Email").fill(process.env.EMAIL ?? "")
await page.getByLabel("Password").fill(process.env.PASSWORD ?? "")
await page.getByRole("button", { name: /sign in/i }).click()
await page.waitForURL(/dashboard/, { timeout: 10_000 })
```

Pull secrets via `op run -- node ...` when they come from 1Password (see the `1password` skill). Never inline credentials in the script itself.

### Scrape structured data

```js
const items = await page.$$eval(".item", (nodes) =>
  nodes.map((el) => ({
    title: el.querySelector(".title")?.textContent?.trim() ?? null,
    href: el.querySelector("a")?.href ?? null
  }))
)
console.log(JSON.stringify({ items }))
```

Prefer `$$eval` over `locator().all()` + `.allTextContents()` when extracting many fields per element — one round-trip vs. N.

### Multi-page flow with checkpointing

```js
await page.goto(url)
await page.getByRole("link", { name: "Settings" }).click()
await page.waitForURL(/settings/)
const beforeSave = await page.content()
await page.getByLabel("Display name").fill("New Name")
await page.getByRole("button", { name: "Save" }).click()
await page.getByText("Saved").waitFor({ state: "visible", timeout: 3000 })
```

### Network capture (for debugging)

```js
const requests = []
page.on("request", (req) => requests.push({ url: req.url(), method: req.method() }))
await page.goto(url)
console.log(JSON.stringify({ requests }))
```

### Headed mode for quick inspection

```js
const browser = await chromium.launch({ headless: false, slowMo: 250 })
```

Fall back to this when an assertion is flaky and you want to see the page step through.

## When to escalate beyond this fallback

- **You need interactive DevTools inspection beyond `abx`.** Use the `chrome-devtools` MCP after recording the verified `abx` limitation.
- **Long autonomous agent loops** where the agent picks the next action at runtime. `browser-use` (Python) is the widely-adopted 2026 choice, but it's an agent framework, not a fallback — use it as a separate task, not from this skill.
- **Deep performance or network profiling** — use the `chrome-devtools` MCP. Do not try to replicate DevTools semantics in a Playwright script.

## Gotchas

- First run is slow (~30s) while Playwright downloads browser binaries. Cache lands in `~/Library/Caches/ms-playwright/`; subsequent runs are fast.
- `networkidle` can hang on pages that keep long-poll connections open. Prefer `domcontentloaded` + an explicit `locator().waitFor()` for the element you care about.
- `page.click()` auto-waits for actionability; don't add manual `waitForTimeout` sleeps on top. If it's flaky, the wrong thing is being waited on.
- Playwright is transitively large (~300MB for Chromium). Don't add it to a project's `devDependencies` just to run a one-off script — `npx playwright@latest` is the right shape for ad-hoc use.
- On Linux CI runners, `--with-deps` installs system libraries (libnss3, etc.). Required once per runner image.
