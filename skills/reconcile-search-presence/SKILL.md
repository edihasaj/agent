---
name: reconcile-search-presence
description: Reconcile app and website discoverability across Google Search Console, Bing Webmaster Tools, DuckDuckGo, Brave Search, and IndexNow. Use when onboarding or updating an app/domain, adding search credentials, fixing indexing or sitemap coverage, installing post-deploy URL notifications, auditing missing provider registrations, or ensuring every active Reachout app remains registered after releases.
---

# Reconcile Search Presence

Keep Reachout as the app inventory and Compass as the desired-vs-actual search
state. Use provider APIs for registration and evidence; never scrape results.

## Start

1. Read `~/Projects/compass/docs/architecture.md` and `docs/usage.md`.
2. Run the production inventory without mutations:

```bash
~/Projects/agent-scripts/skills/reconcile-search-presence/scripts/compass-reconcile --dry-run
```

3. Group failures by shared gate, not app. Fix one credential or ownership gate
   before editing twelve sites independently.
4. Read [references/providers.md](references/providers.md) only for a provider
   that needs setup or verification.

## Reconcile an app addition or update

1. Confirm the active Reachout profile has the canonical `landing_url` and
   `github_url`. Compass discovers it automatically. Inspect the local source
   of truth without writes:

```bash
sqlite3 -readonly ~/Projects/reachout/data/reachout.db \
  "SELECT slug, landing_url, github_url FROM apps WHERE status='active' ORDER BY slug;"
```
2. In the app repository, verify:
   - public `robots.txt` permits crawling;
   - canonical and sitemap URLs use the production origin;
   - `/sitemap.xml` returns valid XML and includes all public pages;
   - the shared IndexNow key file is served from `/<key>.txt`.
3. Copy or invoke the canonical notifier from the repository's successful
   post-deploy hook when pages can change outside the weekly Compass run:

```bash
COMPASS_INDEXNOW_KEY="$COMPASS_INDEXNOW_KEY" \
  ~/Projects/agent-scripts/skills/reconcile-search-presence/scripts/notify_indexnow.py \
  https://example.com/ https://example.com/changed-page
```

   Pass only added, changed, or deleted public URLs. A failed notification must
   fail the post-deploy step visibly, but must not roll back a successful app
   deployment.
4. Commit and deploy the app before search submission. Never submit URLs that
   are not publicly reachable.
5. Preview, then apply:

```bash
~/Projects/agent-scripts/skills/reconcile-search-presence/scripts/compass-reconcile --dry-run
~/Projects/agent-scripts/skills/reconcile-search-presence/scripts/compass-reconcile --apply
```

6. Run the full evidence loop:

```bash
cd ~/Projects/compass
uv run compass seo check
uv run compass seo status
```

7. Report provider status per app and the exact unresolved action.

## Credentials and ownership

- Use the `1password` skill for reusable keys. Keep all `op` commands in one
  fresh tmux session. Never print, paste, or commit secrets.
- Use the `domain-dns-ops` skill for DNS verification records.
- Google automatic sitemap submission requires the `webmasters` OAuth scope
  and Full Search Console permission. A Cloud IAM role alone does not grant
  Search Console property access. Service-account JSON is the production path;
  ADC and short-lived tokens remain supported for local diagnostics.
- Bing has one user-level API key. Adding a site is automatic; DNS ownership is
  a one-time gate.
- DuckDuckGo organic coverage follows Bing. Do not create a separate fake
  integration.
- Brave provides independent result visibility, not webmaster telemetry.
- IndexNow requires a public key file. The key may be shared across owned sites,
  but keep its operational value out of logs.

## Safety

- Default to `--dry-run`.
- Allow only idempotent add, verify, submit, and inspect actions.
- Never delete provider properties, rotate keys, alter DNS, deploy, or push
  without the authority supplied by the current request.
- Preserve account boundaries. Compass routes `github.com/applifyer/*` apps to
  the second Google identity and other apps to the first when creating a
  missing property; verified existing access always wins.
- If an API lacks a supported webmaster action, persist an exact manual action
  instead of browser scraping.

## Always-on contract

Compass runs reconciliation in its weekly workflow when
`COMPASS_SEARCH_AUTO_APPLY=true`. App deploy hooks use
the canonical `notify_indexnow.py` above for immediate changed-URL notification.
Persist the production flag in `/mnt/data/compass/.env`, restart
`compass.service` and `compass-weekly.timer`, then verify:

```bash
ssh -o IdentitiesOnly=yes \
  -i ~/.ssh/basevm_clean_20260724_ed25519 baseadmin@135.220.98.13 \
  'systemctl is-active compass.service compass-weekly.timer'
```

A new active Reachout app therefore enters the next reconciliation
automatically, while each release can notify participating engines immediately.

## Public validation

Use the real production origin after deployment:

```bash
curl -fsSI https://example.com/
curl -fsS https://example.com/robots.txt
curl -fsS https://example.com/sitemap.xml | xmllint --noout -
```

Compare sitemap URLs with the app's intended public routes. Do not infer that
private, authenticated, callback, or API routes belong in the sitemap.
