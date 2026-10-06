"""Shared helpers: drive the signed-in agent Chrome over CDP with Playwright.

Play Console and App Store Connect are Angular/React apps whose radios and
checkboxes are custom elements, so these helpers act on what a person sees
(labels, roles, debug ids) rather than on brittle CSS paths.
"""

from __future__ import annotations

import contextlib
import os
import re
import sys
import time
from typing import Iterator

from playwright.sync_api import Page, sync_playwright

CDP_URL = os.environ.get("ABX_LIVE_CDP_URL", "http://127.0.0.1:9223")


def log(message: str) -> None:
    print(message, flush=True)


def die(message: str, code: int = 1) -> None:
    print(f"error: {message}", file=sys.stderr, flush=True)
    raise SystemExit(code)


@contextlib.contextmanager
def tab(host: str) -> Iterator[Page]:
    """Reuse a tab already on `host` (keeps its session), else open one."""
    with sync_playwright() as pw:
        try:
            browser = pw.chromium.connect_over_cdp(CDP_URL)
        except Exception as error:  # noqa: BLE001 - surface the CDP problem plainly
            die(f"cannot reach the agent Chrome at {CDP_URL} ({error}); run chrome-agent start")
        context = browser.contexts[0]
        page = next((p for p in context.pages if host in p.url), None) or context.new_page()
        page.bring_to_front()
        yield page


def goto(page: Page, url: str, settle: float = 6) -> None:
    page.goto(url, wait_until="domcontentloaded", timeout=90_000)
    time.sleep(settle)
    if "accounts.google.com" in page.url or "/login" in page.url or "idmsa.apple.com" in page.url:
        die(f"not signed in ({page.url}); a person must sign in in the agent Chrome first", 3)


def body(page: Page) -> str:
    return page.inner_text("body")


def wait_for_text(page: Page, pattern: str, timeout: float = 20) -> bool:
    regex = re.compile(pattern, re.I)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if regex.search(body(page)):
            return True
        time.sleep(0.5)
    return False


def button(page: Page, name: str, *, timeout: float = 15) -> None:
    """Click the last visible, enabled button whose accessible name is `name`."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        buttons = page.get_by_role("button", name=name, exact=True)
        for i in reversed(range(buttons.count())):
            candidate = buttons.nth(i)
            if candidate.is_visible() and candidate.is_enabled():
                candidate.click()
                return
        time.sleep(0.5)
    die(f"button '{name}' not found or disabled on {page.url}")


def has_button(page: Page, name: str) -> bool:
    buttons = page.get_by_role("button", name=name, exact=True)
    return any(buttons.nth(i).is_visible() for i in range(buttons.count()))


def try_button(page: Page, name: str) -> bool:
    """Click a visible, enabled button if there is one; never fails."""
    buttons = page.get_by_role("button", name=name, exact=True)
    for i in reversed(range(buttons.count())):
        candidate = buttons.nth(i)
        if candidate.is_visible() and candidate.is_enabled():
            candidate.click()
            return True
    return False


def choose(page: Page, text: str | None = None, *, debug_id: str | None = None) -> None:
    """Tick a Material radio or checkbox by its visible text (regex) or debug id."""
    found = page.evaluate(
        """([pattern, debugId]) => {
            const re = pattern ? new RegExp(pattern) : null;
            const all = Array.from(document.querySelectorAll('material-radio, material-checkbox'))
              .filter(e => e.offsetParent);
            const el = debugId
              ? all.find(e => e.getAttribute('debug-id') === debugId)
              : all.find(e => re.test(e.textContent.trim()));
            if (!el) return false;
            const input = el.querySelector('input');
            if (!input.checked) input.click();
            return true;
        }""",
        [text, debug_id],
    )
    if not found:
        die(f"option {debug_id or text!r} not found on {page.url}")


def answer_no_to_all(page: Page) -> list[str]:
    """Answer 'No' in every unanswered Yes/No group; returns the questions."""
    return page.evaluate(
        """() => {
            const out = [];
            for (const group of document.querySelectorAll('material-radio-group')) {
              if (!group.offsetParent) continue;
              const radios = Array.from(group.querySelectorAll('material-radio'));
              if (radios.some(r => r.querySelector('input').checked)) continue;
              const no = radios.find(r => /^No\\b/.test(r.textContent.trim()));
              let q = group; for (let i = 0; i < 4 && q; i++) q = q.parentElement;
              const text = (q ? q.textContent : '').replace(/\\s+/g, ' ').replace(/YesNo/g, '').trim();
              if (no) { no.querySelector('input').click(); out.push('No: ' + text.slice(0, 160)); }
              else out.push('UNANSWERED: ' + text.slice(0, 160));
            }
            return out;
        }"""
    )


def fill_label(page: Page, label: str, value: str, nth: int = 0) -> None:
    """Fill the nth visible field with this accessible label (works with Angular)."""
    fields = page.get_by_label(label, exact=True)
    visible = [fields.nth(i) for i in range(fields.count()) if fields.nth(i).is_visible()]
    if len(visible) <= nth:
        die(f"field '{label}' not found on {page.url}")
    visible[nth].fill(value)


def save_or_discard(page: Page, dry_run: bool, *, save: str = "Save") -> None:
    """Persist the form, or in dry-run mode leave it unsaved and say so."""
    page.screenshot(path="/tmp/store-console-last.png")
    if dry_run:
        log(f"dry run: filled {page.url} without saving (screenshot /tmp/store-console-last.png)")
        # Unsaved edits are dropped when the next step navigates away; close
        # any edit dialog first so nothing lingers on screen.
        for name in ("Discard changes", "Discard", "Cancel"):
            if try_button(page, name):
                break
        return
    button(page, save)
    if not wait_for_text(page, r"Change saved|changes have been saved|Questionnaire saved"):
        errors = "fix errors" in body(page)
        die(f"save not confirmed on {page.url}" + (" (form reports errors)" if errors else ""))
    log(f"saved {page.url}")
