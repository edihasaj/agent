#!/usr/bin/env python3
"""Notify IndexNow about changed URLs without exposing the configured key."""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("urls", nargs="+", help="public URLs added, changed, or deleted")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    key = os.environ.get("COMPASS_INDEXNOW_KEY") or os.environ.get("INDEXNOW_KEY")
    if not key:
        parser.error("set COMPASS_INDEXNOW_KEY or INDEXNOW_KEY")

    hosts = {urlparse(url).hostname for url in args.urls}
    if None in hosts or len(hosts) != 1:
        parser.error("all URLs must be absolute and belong to one host")
    host = next(iter(hosts))
    if not all(urlparse(url).scheme in {"http", "https"} for url in args.urls):
        parser.error("all URLs must use http or https")

    key_location = f"https://{host}/{key}.txt"
    if args.dry_run:
        print(json.dumps({"host": host, "urls": len(args.urls), "status": "planned"}))
        return 0

    try:
        with urllib.request.urlopen(key_location, timeout=15) as response:
            if response.status != 200 or response.read().decode().strip() != key:
                raise RuntimeError("public IndexNow key file does not match")
        payload = json.dumps(
            {
                "host": host,
                "key": key,
                "keyLocation": key_location,
                "urlList": args.urls,
            }
        ).encode()
        request = urllib.request.Request(
            "https://api.indexnow.org/indexnow",
            data=payload,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            status = response.status
    except (urllib.error.URLError, RuntimeError) as exc:
        print(f"IndexNow submission failed: {exc}", file=sys.stderr)
        return 1

    print(json.dumps({"host": host, "urls": len(args.urls), "status": status}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
