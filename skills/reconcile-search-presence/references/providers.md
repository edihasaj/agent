# Provider gates

Read only the provider section needed for the current failure.

## Google Search Console

- Credential: one or more service-account JSON files.
- Cloud requirement: Search Console API enabled in each service-account project.
- Property requirement: Domain property such as `sc-domain:example.com`.
- Read checks: Restricted/read property access is sufficient.
- Automatic property and sitemap actions: Full property permission plus
  `https://www.googleapis.com/auth/webmasters`.
- Verification: use Search Console ownership flow and DNS when required.
- Compass setting:
  `COMPASS_GSC_SERVICE_ACCOUNT_FILES=/secure/personal.json,/secure/applifyer.json`.

## Bing and DuckDuckGo

- Credential: one Bing Webmaster API key per user, shared by that user's sites.
- Compass automatically calls `AddSite`, `VerifySite`, `SubmitFeed`, and
  `SubmitUrl`.
- If verification remains pending, use the returned DNS verification target
  through `domain-dns-ops`, wait for DNS, then rerun.
- DuckDuckGo sources most organic links from Bing, so mirror Bing readiness.

## Brave

- Credential: Brave Search API subscription token.
- Check `site:<domain>` through the official API.
- Treat results as presence evidence only. Brave has no equivalent first-party
  click/impression webmaster feed.
- Missing results: verify ordinary crawlability, then use Brave's supported
  re-fetch/feedback path at
  `https://search.brave.com/help/brave-search-crawler`. Do not scrape consumer
  results.

## IndexNow

- Credential: 8 to 128 character key in `COMPASS_INDEXNOW_KEY`.
- Ownership: serve the exact key at `https://domain/<key>.txt`.
- Submit only public URLs belonging to that host.
- Invoke
  `~/Projects/agent/skills/reconcile-search-presence/scripts/notify_indexnow.py`
  with one or more absolute changed URLs in successful deploy hooks. Use
  `--dry-run` to validate arguments without network access. Compass also
  performs a weekly portfolio submission.
- One successful IndexNow endpoint submission is shared with participating
  engines.

## Other engines

- Add a provider only when it offers an official webmaster or submission API
  and the app targets its market.
- Prefer IndexNow participation before bespoke integrations.
- Persist unsupported providers as exact manual actions. Never automate
  consumer-result scraping.
