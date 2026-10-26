---
name: brave-search
description: Web search and page extraction through configured private SearXNG or the Brave Search API. Use for finding documentation, facts, and current web sources. No browser required.
---

# Web Search

Use the existing search helper for web research. It selects private SearXNG when
`~/.config/agent-search/client.json` exists; otherwise it retains the Brave API
default. Page extraction works independently of either search provider.

## Setup

Run once before first use:

```bash
cd ~/Projects/agent/skills/brave-search
npm ci
```

Private SearXNG uses an owner-only (0600) client JSON file containing `url`
(the HTTPS origin) and `token`. `AGENT_SEARCH_CONFIG` can select another file.
Keep this file outside repositories. Do not read or print its credential.
`SEARCH_PROVIDER=searxng|brave` or `--provider` explicitly selects a provider.

Private searches use the shared cache and rotate available engines. Failures
never trigger paid Brave fallback. Use `--provider brave` only when paid search
is appropriate for the request; it requires `BRAVE_API_KEY` and makes a billable
API request. `--content` fetches result pages directly and adds no search calls.

## Search

```bash
./search.js "query"                    # Basic search (5 results)
./search.js "query" -n 10              # More results
./search.js "query" --content          # Include page content as markdown
./search.js "query" -n 3 --content     # Combined
./search.js "query" --profile code    # Code sources plus web engines
./search.js "query" --profile science # Academic and reference sources
./search.js "query" --engines google,bing # Explicit engines, same shared limits
```

The CLI accepts 1–20 results. The private API supports the first page and
rejects engine-selection bangs in query text; use `--engines` instead. Respect
its returned retry delay when all selected engines are busy or cooling down.
Broaden a sparse search or select another relevant profile rather than
repeating an unchanged query. The paid Brave mode retries transient `429`
responses using Brave's reset header.

## Extract Page Content

```bash
./content.js https://example.com/article
```

Fetches a URL and extracts readable content as markdown.

## Output Format

```
--- Result 1 ---
Title: Page Title
Link: https://example.com/page
Snippet: Description from search results
Content: (if --content flag used)
  Markdown content extracted from the page...

--- Result 2 ---
...
```

## When to Use

- Searching for documentation or API references
- Looking up facts or current information
- Fetching content from specific URLs
- Any task requiring web search without interactive browsing
