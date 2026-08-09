---
name: favicon-generator
description: Generate favicons, app icons, manifests, and SEO files (robots.txt, sitemap.xml, agents.txt, llms.txt) plus a paste-ready HTML head snippet from a single source image. Mirrors favicon-generator.org output. Use when the user asks for favicons, app icons, web manifest, or "set up SEO files" for a site/app. Supports web, ios, android, windows, macos (.icns), linux (hicolor + .desktop).
---

# Favicon & SEO Generator

One CLI, one source image → full set of platform icons + manifest + SEO files + HTML snippet.

## When to use

- "Generate favicons for ./<project>"
- "Make app icons for web / iOS / Android / macOS / Linux / Windows"
- "Set up robots.txt / sitemap.xml / agents.txt"
- "I have a logo, give me everything to drop into the public folder"

## Source image

Need a square PNG or SVG, ideally **1024×1024+**. Non-square inputs are auto-padded to square on a transparent background.

If the user has no source image, generate one first using the `nano-banana-pro` skill (resolution 1K is enough — 4K is overkill for icons), then pass that file to `--source`.

## Run it

```bash
python3 ~/Projects/agent/skills/favicon-generator/scripts/favicon.py \
  --source ./logo.png \
  --out ./public \
  --platforms web \
  --site-url https://example.com \
  --name "My App" \
  --short-name "My App" \
  --description "One-line app description" \
  --theme-color "#0a0f1a" \
  --bg-color "#0a0f1a" \
  --pages "/,/about,/pricing,/privacy,/terms"
```

Always run from the user's working directory; `--out` defaults to `./public`.

## Platforms

Pass `--platforms` as a comma-separated list. Default: `web`.

| value | what it produces |
| --- | --- |
| `web` | favicon.ico (16/32/48), favicon-{16,32,48,96,192,512}.png, apple-icon-*.png, android-icon-*.png, ms-icon-*.png, manifest.json, browserconfig.xml |
| `ios` | apple-icon-{57..180}.png + apple-touch-icon.png + apple-icon-precomposed.png |
| `android` | android-icon-{36..192}.png + manifest.json |
| `windows` | ms-icon-{70,144,150,310}.png + browserconfig.xml |
| `macos` | AppIcon.iconset/ + AppIcon.icns (via `iconutil`) |
| `linux` | hicolor/{16..512}/apps/<slug>.png + sample <slug>.desktop |
| `all` | every platform above |

`web` already includes apple/android/ms icons (manifest needs them). Pick `ios`/`android`/`windows` only if the user explicitly wants just one of those.

## SEO files (default on)

Generated unless `--no-seo`:

- `robots.txt` — common bots allow-listed; appends `Sitemap:` line if `--site-url` is set.
- `sitemap.xml` — only if `--site-url` is set; uses `--pages` (defaults to `/`).
- `agents.txt` — AI crawler policy. Allow-list by default; pass `--block-ai` to disallow major LLM bots (GPTBot, ClaudeBot, anthropic-ai, PerplexityBot, Google-Extended, Applebot-Extended, CCBot, etc.).
- `llms.txt` — short LLM-friendly site index (name, description, home link).

## HTML snippet

Writes `head-snippet.html` (unless `--no-html`) with all the right `<link>` and `<meta>` tags. Tell the user to paste it into their `<head>`. Adapts to the platforms requested (skips Apple links for android-only runs, etc.).

## Reference layout

This is the layout the CLI produces for `--platforms web`. It matches favicon-generator.org's output, which is what `~/Projects/chirp-go-landing/public/` already uses, so it drops straight into existing setups.

```
public/
  android-icon-36x36.png … android-icon-192x192.png
  apple-icon-57x57.png  … apple-icon-180x180.png
  apple-icon.png  apple-icon-precomposed.png  apple-touch-icon.png
  favicon-16x16.png … favicon-512x512.png
  favicon.ico        # multi-res 16/32/48
  ms-icon-70x70.png … ms-icon-310x310.png
  manifest.json
  browserconfig.xml
  robots.txt sitemap.xml agents.txt llms.txt
  head-snippet.html
  logo.png           # 512px master copy
```

## Required tools

- `magick` (ImageMagick 7+) — required, all resizing + .ico
- `iconutil` — macOS native, used for `.icns`. If missing, `.iconset` is still produced.

Both already installed on this machine.

## Safety / overwrite

Re-running the CLI **always overwrites PNGs/.ico** (cheap to regenerate). Text files (manifest.json, robots.txt, sitemap.xml, agents.txt, llms.txt, browserconfig.xml, head-snippet.html) are **kept** if they already exist — pass `--overwrite` to replace them. This protects user-customized robots/sitemap content.

## Common recipes

**Web project, full set:**
```bash
python3 ~/Projects/agent/skills/favicon-generator/scripts/favicon.py \
  --source ./logo.png --out ./public --platforms web \
  --site-url https://chirpgo.app --name "Chirp Go" \
  --description "On-device AI voice-to-text for macOS" \
  --theme-color "#0a0f1a" --bg-color "#0a0f1a" \
  --pages "/,/privacy,/terms,/refund,/download"
```

**Generate logo first via nano-banana-pro, then favicons:**
```bash
# 1) generate source
uv run ~/Projects/agent/skills/nano-banana-pro/scripts/generate_image.py \
  --prompt "minimalist app icon: <description>" \
  --filename "logo.png" --resolution 1K
# 2) generate favicons
python3 ~/Projects/agent/skills/favicon-generator/scripts/favicon.py \
  --source ./logo.png --platforms all --site-url https://example.com --name "App"
```

**Native macOS app — .icns only:**
```bash
python3 ~/Projects/agent/skills/favicon-generator/scripts/favicon.py \
  --source ./icon.png --out ./Resources --platforms macos --no-seo --no-html
```

**Block AI crawlers:**
```bash
python3 ~/Projects/agent/skills/favicon-generator/scripts/favicon.py \
  --source ./logo.png --site-url https://example.com --block-ai
```
