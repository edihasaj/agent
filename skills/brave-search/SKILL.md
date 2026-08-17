---
name: brave-search
description: Web search and content extraction via Brave Search API. Use for searching documentation, facts, or any web content. Lightweight, no browser required.
---

# Brave Search

Headless web search through the official Brave Search API plus direct page content extraction. No browser required.

## Setup

Run once before first use:

```bash
cd ~/Projects/agent/skills/brave-search
npm ci
```

Needs env: `BRAVE_API_KEY`.

Each `search.js` invocation makes one billable Brave Search API request. `--content` fetches result pages directly and does not add Brave API requests.

## Search

```bash
./search.js "query"                    # Basic search (5 results)
./search.js "query" -n 10              # More results
./search.js "query" --content          # Include page content as markdown
./search.js "query" -n 3 --content     # Combined
```

The CLI accepts 1-20 results and retries transient `429` responses using Brave's rate-limit reset header.

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
