#!/usr/bin/env python3
"""
favicon CLI — generate favicons, app icons, manifests, and SEO files from one source image.

Mirrors the favicon-generator.org output layout (apple-icon-*, android-icon-*, ms-icon-*,
favicon-*, favicon.ico, manifest.json, browserconfig.xml) and adds robots.txt, sitemap.xml,
agents.txt, llms.txt, and a paste-ready HTML <head> snippet.

Platforms:
  web (default)   — full web set + ios/android/windows icons + manifest.json + browserconfig.xml
  ios             — apple-icon-{57..180}.png + apple-touch-icon.png + apple-icon-precomposed.png
  android         — android-icon-{36..192}.png + manifest.json
  windows         — ms-icon-{70,144,150,310}.png + browserconfig.xml
  macos           — AppIcon.iconset + AppIcon.icns (via iconutil)
  linux           — hicolor theme PNGs + sample .desktop file
  all             — every platform above

Backends: ImageMagick `magick` (required), `iconutil` (macOS, for .icns), `sips` (macOS, fallback).
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Iterable, Sequence

WEB_FAVICON_PNG = [16, 32, 48, 96, 192, 512]
ICO_SIZES = [16, 32, 48]
APPLE_SIZES = [57, 60, 72, 76, 114, 120, 144, 152, 180]
ANDROID_SIZES = [36, 48, 72, 96, 144, 192]
MS_TILES = [70, 144, 150, 310]
MACOS_ICONSET = [16, 32, 64, 128, 256, 512, 1024]  # plus @2x variants
LINUX_HICOLOR = [16, 22, 24, 32, 48, 64, 128, 256, 512]

PLATFORMS = {"web", "ios", "android", "windows", "macos", "linux", "all"}

DEFAULT_AI_AGENTS_ALLOW = [
    "GPTBot", "ChatGPT-User", "ClaudeBot", "Claude-Web", "anthropic-ai",
    "PerplexityBot", "Google-Extended", "Applebot-Extended", "CCBot",
    "Bytespider", "FacebookBot", "DuckAssistBot", "MistralAI-User",
]


@dataclass
class Config:
    source: Path
    out: Path
    platforms: set[str]
    site_url: str | None
    name: str
    short_name: str
    description: str
    theme_color: str
    bg_color: str
    pages: list[str]
    seo: bool
    html: bool
    block_ai: bool
    overwrite: bool
    extra_files: list[str] = field(default_factory=list)


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def need(cmd: str) -> str:
    path = shutil.which(cmd)
    if not path:
        die(f"required command not found: {cmd}")
    return path


def run(cmd: Sequence[str]) -> None:
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        die(f"{' '.join(cmd[:2])} failed: {res.stderr.strip() or res.stdout.strip()}")


def ensure_square_source(src: Path) -> Path:
    """If source is non-square, pad to square on transparent background."""
    magick = need("magick")
    res = subprocess.run([magick, "identify", "-format", "%w %h", str(src)],
                         capture_output=True, text=True)
    if res.returncode != 0:
        die(f"cannot read {src}: {res.stderr.strip()}")
    w, h = map(int, res.stdout.split())
    if w == h:
        return src
    side = max(w, h)
    padded = src.parent / f".__favicon_padded_{src.stem}.png"
    run([magick, str(src), "-background", "none", "-gravity", "center",
         "-extent", f"{side}x{side}", str(padded)])
    return padded


def render_png(src: Path, out: Path, size: int) -> None:
    magick = need("magick")
    run([magick, str(src), "-background", "none",
         "-resize", f"{size}x{size}",
         "-define", "png:color-type=6", str(out)])


def render_ico(src: Path, out: Path, sizes: Iterable[int]) -> None:
    """Multi-resolution ICO."""
    magick = need("magick")
    args = [magick, str(src), "-background", "none"]
    for s in sizes:
        args += ["(", "-clone", "0", "-resize", f"{s}x{s}", ")"]
    args += ["-delete", "0", str(out)]
    run(args)


def render_macos_icns(src: Path, out_dir: Path) -> None:
    iconset = out_dir / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    pairs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    for size, name in pairs:
        render_png(src, iconset / name, size)
    iconutil = shutil.which("iconutil")
    if iconutil:
        run([iconutil, "-c", "icns", str(iconset), "-o", str(out_dir / "AppIcon.icns")])
    else:
        print("note: iconutil not found (macOS only) — .iconset created, .icns skipped",
              file=sys.stderr)


def render_linux_hicolor(src: Path, out_dir: Path, name: str) -> None:
    base = out_dir / "hicolor"
    for s in LINUX_HICOLOR:
        d = base / f"{s}x{s}" / "apps"
        d.mkdir(parents=True, exist_ok=True)
        render_png(src, d / f"{name}.png", s)
    # sample .desktop file
    desktop = out_dir / f"{name}.desktop"
    if not desktop.exists():
        desktop.write_text(
            f"""[Desktop Entry]
Name={name}
Exec={name}
Icon={name}
Type=Application
Categories=Utility;
""")


def write_manifest(cfg: Config) -> dict:
    return {
        "name": cfg.name,
        "short_name": cfg.short_name,
        "description": cfg.description,
        "start_url": "/",
        "display": "standalone",
        "background_color": cfg.bg_color,
        "theme_color": cfg.theme_color,
        "icons": [
            {"src": "/favicon-16x16.png", "sizes": "16x16", "type": "image/png"},
            {"src": "/favicon-32x32.png", "sizes": "32x32", "type": "image/png"},
            {"src": "/favicon-96x96.png", "sizes": "96x96", "type": "image/png"},
            {"src": "/android-icon-192x192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "/favicon-512x512.png", "sizes": "512x512", "type": "image/png"},
        ],
    }


def write_browserconfig() -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<browserconfig><msapplication><tile>"
        '<square70x70logo src="/ms-icon-70x70.png"/>'
        '<square150x150logo src="/ms-icon-150x150.png"/>'
        '<square310x310logo src="/ms-icon-310x310.png"/>'
        "<TileColor>#ffffff</TileColor>"
        "</tile></msapplication></browserconfig>\n"
    )


def write_robots(cfg: Config) -> str:
    lines = [
        "User-agent: Googlebot", "Allow: /", "",
        "User-agent: Bingbot", "Allow: /", "",
        "User-agent: Twitterbot", "Allow: /", "",
        "User-agent: facebookexternalhit", "Allow: /", "",
        "User-agent: *", "Allow: /", "",
    ]
    if cfg.site_url:
        lines.append(f"Sitemap: {cfg.site_url.rstrip('/')}/sitemap.xml")
    return "\n".join(lines) + "\n"


def write_sitemap(cfg: Config) -> str:
    if not cfg.site_url:
        return ""
    today = date.today().isoformat()
    base = cfg.site_url.rstrip("/")
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for i, p in enumerate(cfg.pages):
        loc = base + (p if p.startswith("/") else "/" + p)
        priority = "1.0" if p in ("/", "") else "0.7" if i < 3 else "0.5"
        freq = "weekly" if p in ("/", "") else "monthly"
        out += [
            "  <url>",
            f"    <loc>{loc}</loc>",
            f"    <lastmod>{today}</lastmod>",
            f"    <changefreq>{freq}</changefreq>",
            f"    <priority>{priority}</priority>",
            "  </url>",
        ]
    out.append("</urlset>")
    return "\n".join(out) + "\n"


def write_agents_txt(cfg: Config) -> str:
    """ai.txt / agents.txt — emerging robots-for-AI standard."""
    if cfg.block_ai:
        body = ["# AI/LLM crawler policy — block all\n"]
        for ua in DEFAULT_AI_AGENTS_ALLOW:
            body += [f"User-agent: {ua}", "Disallow: /", ""]
        body += ["User-agent: *", "Disallow: /"]
    else:
        body = ["# AI/LLM crawler policy — allow listed bots\n"]
        for ua in DEFAULT_AI_AGENTS_ALLOW:
            body += [f"User-agent: {ua}", "Allow: /", ""]
    return "\n".join(body) + "\n"


def write_llms_txt(cfg: Config) -> str:
    site = cfg.site_url or "https://example.com"
    return (
        f"# {cfg.name}\n\n"
        f"> {cfg.description}\n\n"
        f"- [Home]({site})\n"
    )


def write_html_snippet(cfg: Config) -> str:
    has_apple = "ios" in cfg.platforms or "web" in cfg.platforms or "all" in cfg.platforms
    has_ms = "windows" in cfg.platforms or "web" in cfg.platforms or "all" in cfg.platforms
    has_manifest = "web" in cfg.platforms or "android" in cfg.platforms or "all" in cfg.platforms
    out = ["<!-- Favicons (generated) -->"]
    if has_apple:
        for s in APPLE_SIZES:
            out.append(f'<link rel="apple-touch-icon" sizes="{s}x{s}" href="/apple-icon-{s}x{s}.png" />')
    out.append('<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />')
    out.append('<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />')
    out.append('<link rel="icon" type="image/png" sizes="96x96" href="/favicon-96x96.png" />')
    out.append('<link rel="icon" type="image/png" sizes="192x192" href="/android-icon-192x192.png" />')
    out.append('<link rel="icon" type="image/png" sizes="512x512" href="/favicon-512x512.png" />')
    out.append('<link rel="shortcut icon" href="/favicon.ico" />')
    if has_manifest:
        out.append('<link rel="manifest" href="/manifest.json" />')
    if has_ms:
        out.append(f'<meta name="msapplication-TileColor" content="#ffffff" />')
        out.append('<meta name="msapplication-TileImage" content="/ms-icon-144x144.png" />')
        out.append('<meta name="msapplication-config" content="/browserconfig.xml" />')
    out.append(f'<meta name="theme-color" content="{cfg.theme_color}" />')
    return "\n".join(out) + "\n"


def write_text(path: Path, content: str, overwrite: bool) -> None:
    if path.exists() and not overwrite:
        print(f"skip (exists): {path.name}", file=sys.stderr)
        return
    path.write_text(content)


def generate(cfg: Config) -> None:
    cfg.out.mkdir(parents=True, exist_ok=True)
    src = ensure_square_source(cfg.source)
    plats = cfg.platforms
    do = lambda p: ("all" in plats) or (p in plats)

    # web favicons
    if do("web"):
        for s in WEB_FAVICON_PNG:
            render_png(src, cfg.out / f"favicon-{s}x{s}.png", s)
        render_ico(src, cfg.out / "favicon.ico", ICO_SIZES)
        # canonical "favicon.png" copy at 512
        render_png(src, cfg.out / "logo.png", 512)

    # ios / apple
    if do("web") or do("ios"):
        for s in APPLE_SIZES:
            render_png(src, cfg.out / f"apple-icon-{s}x{s}.png", s)
        # canonical apple-touch-icon (180) + precomposed + apple-icon.png
        render_png(src, cfg.out / "apple-touch-icon.png", 180)
        render_png(src, cfg.out / "apple-icon.png", 192)
        render_png(src, cfg.out / "apple-icon-precomposed.png", 192)

    # android
    if do("web") or do("android"):
        for s in ANDROID_SIZES:
            render_png(src, cfg.out / f"android-icon-{s}x{s}.png", s)

    # windows tiles
    if do("web") or do("windows"):
        for s in MS_TILES:
            render_png(src, cfg.out / f"ms-icon-{s}x{s}.png", s)
        write_text(cfg.out / "browserconfig.xml", write_browserconfig(), cfg.overwrite)

    # manifest (web/android)
    if do("web") or do("android"):
        write_text(cfg.out / "manifest.json",
                   json.dumps(write_manifest(cfg), indent=2) + "\n",
                   cfg.overwrite)

    # macos
    if do("macos"):
        render_macos_icns(src, cfg.out)

    # linux
    if do("linux"):
        slug = cfg.short_name.lower().replace(" ", "-") or "app"
        render_linux_hicolor(src, cfg.out, slug)

    # SEO
    if cfg.seo:
        write_text(cfg.out / "robots.txt", write_robots(cfg), cfg.overwrite)
        if cfg.site_url:
            write_text(cfg.out / "sitemap.xml", write_sitemap(cfg), cfg.overwrite)
        write_text(cfg.out / "agents.txt", write_agents_txt(cfg), cfg.overwrite)
        write_text(cfg.out / "llms.txt", write_llms_txt(cfg), cfg.overwrite)

    # HTML snippet
    if cfg.html:
        write_text(cfg.out / "head-snippet.html", write_html_snippet(cfg), cfg.overwrite)

    # cleanup tempfile
    if src != cfg.source and src.name.startswith(".__favicon_padded_"):
        src.unlink(missing_ok=True)


def parse_args(argv: list[str]) -> Config:
    ap = argparse.ArgumentParser(
        prog="favicon",
        description="Generate favicons, app icons, manifests, and SEO files from one source image.",
    )
    ap.add_argument("--source", required=True, type=Path,
                    help="Source image (PNG or SVG, ideally 1024x1024+ square).")
    ap.add_argument("--out", type=Path, default=Path("./public"),
                    help="Output directory (default: ./public).")
    ap.add_argument("--platforms", default="web",
                    help=f"Comma-separated: {','.join(sorted(PLATFORMS))} (default: web).")
    ap.add_argument("--site-url", default=None,
                    help="Canonical site URL (enables sitemap.xml + robots Sitemap directive).")
    ap.add_argument("--name", default="App", help="App name (manifest).")
    ap.add_argument("--short-name", default=None, help="Short name (manifest, default: --name).")
    ap.add_argument("--description", default="", help="App description (manifest, llms.txt).")
    ap.add_argument("--theme-color", default="#0a0f1a")
    ap.add_argument("--bg-color", default="#0a0f1a")
    ap.add_argument("--pages", default="/",
                    help="Comma-separated paths for sitemap (default: /).")
    ap.add_argument("--no-seo", action="store_true",
                    help="Skip robots.txt / sitemap.xml / agents.txt / llms.txt.")
    ap.add_argument("--no-html", action="store_true",
                    help="Skip head-snippet.html.")
    ap.add_argument("--block-ai", action="store_true",
                    help="agents.txt blocks AI crawlers (default: allow).")
    ap.add_argument("--overwrite", action="store_true",
                    help="Overwrite existing text files (manifest/robots/sitemap/etc).")
    args = ap.parse_args(argv)

    if not args.source.exists():
        die(f"source not found: {args.source}")

    plats = {p.strip().lower() for p in args.platforms.split(",") if p.strip()}
    bad = plats - PLATFORMS
    if bad:
        die(f"unknown platform(s): {','.join(sorted(bad))} (valid: {','.join(sorted(PLATFORMS))})")

    return Config(
        source=args.source.resolve(),
        out=args.out.resolve(),
        platforms=plats,
        site_url=args.site_url,
        name=args.name,
        short_name=args.short_name or args.name,
        description=args.description,
        theme_color=args.theme_color,
        bg_color=args.bg_color,
        pages=[p.strip() for p in args.pages.split(",") if p.strip()],
        seo=not args.no_seo,
        html=not args.no_html,
        block_ai=args.block_ai,
        overwrite=args.overwrite,
    )


def main(argv: list[str] | None = None) -> int:
    cfg = parse_args(argv if argv is not None else sys.argv[1:])
    need("magick")
    generate(cfg)
    print(f"\n✓ wrote to: {cfg.out}")
    print(f"  platforms: {', '.join(sorted(cfg.platforms))}")
    if cfg.html:
        print(f"  paste into <head>: {cfg.out / 'head-snippet.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
