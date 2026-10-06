"""App Store Connect and developer-portal steps the App Store Connect API cannot do.

Covered: create the app record (the API refuses `apps` CREATE), publish the
App Privacy answer "Data Not Collected", register an App Group, and assign an
App Group to a bundle ID (App Groups have no public endpoints).

Bundle IDs, capabilities, certificates, profiles, versions, localizations,
screenshots, age rating, pricing, availability, builds and review submission
all have App Store Connect API endpoints — use those instead.
"""

from __future__ import annotations

import argparse
import re
import time

from console_common import body, button, die, goto, has_button, log, tab, wait_for_text

ASC = "https://appstoreconnect.apple.com"
PORTAL = "https://developer.apple.com/account/resources"


def react_select(page, selector: str, value: str | None = None, text: str | None = None) -> str:
    """Set a React-controlled <select> by option value or visible text."""
    return page.evaluate(
        """([selector, value, text]) => {
            const el = document.querySelector(selector);
            if (!el) return 'missing';
            const opt = Array.from(el.options).find(o => value ? o.value === value : o.text.trim() === text);
            if (!opt) return 'no-option';
            Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(el, opt.value);
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return opt.value;
        }""",
        [selector, value, text],
    )


def create_app(a) -> None:
    with tab("appstoreconnect.apple.com") as page:
        goto(page, f"{ASC}/apps")
        button(page, "New App")
        time.sleep(1)
        page.locator("li", has_text=re.compile(r"^New App$")).locator("button, a").first.click()
        time.sleep(2)
        page.locator(f"#platformsById\\.{a.platform}").check()
        page.locator("input[name=name]").fill(a.name)
        if react_select(page, "select[name=primaryLocale]", text=a.locale) in ("missing", "no-option"):
            die(f"primary language '{a.locale}' not offered")
        if react_select(page, "select[name=bundleId]", value=a.bundle_id) in ("missing", "no-option"):
            die(f"bundle ID {a.bundle_id} is not registered for this team (register it via the API first)")
        page.locator("input[name=sku]").fill(a.sku)
        page.locator("#userAccessFull").check()
        page.screenshot(path="/tmp/store-console-last.png")
        if a.dry_run:
            log("dry run: New App form filled, not created (screenshot /tmp/store-console-last.png)")
            button(page, "Cancel")
            return
        button(page, "Create")
        deadline = time.time() + 30
        while time.time() < deadline and not re.search(r"/apps/\d+", page.url):
            errors = page.evaluate(
                """() => Array.from(document.querySelectorAll('[role=alert],[class*=error]'))
                     .filter(e => e.offsetParent).map(e => e.textContent.trim()).filter(Boolean).join(' | ')""")
            if errors:
                die(f"App Store Connect refused the app: {errors[:300]}")
            time.sleep(1)
        match = re.search(r"/apps/(\d+)", page.url)
        log(f"created app {match.group(1)}" if match else
            "created (no redirect seen); find the Apple ID with GET /v1/apps?filter[bundleId]=" + a.bundle_id)


def privacy_not_collected(a) -> None:
    with tab("appstoreconnect.apple.com") as page:
        goto(page, f"{ASC}/apps/{a.app}/distribution/privacy", settle=8)
        if "Data Not Collected" in body(page) and not has_button(page, "Get Started"):
            log("App Privacy already answered 'Data Not Collected'")
        else:
            if has_button(page, "Get Started"):
                button(page, "Get Started")
            else:
                button(page, "Edit")
            time.sleep(2)
            page.locator("#CONFIRM_COLLECT_DATA_radio_false").check()
            if a.dry_run:
                log("dry run: 'No, we do not collect data' selected, not saved")
                button(page, "Cancel")
                return
            button(page, "Save")
            time.sleep(3)
        if a.dry_run:
            return
        if has_button(page, "Publish"):
            button(page, "Publish")
            time.sleep(2)
            button(page, "Publish")  # confirmation dialog
            if not wait_for_text(page, r"Published .* ago", 20):
                die("publish not confirmed")
        log("App Privacy published: Data Not Collected")


def app_group(a) -> None:
    if not a.identifier.startswith("group."):
        die("App Group identifiers start with 'group.'")
    with tab("developer.apple.com") as page:
        goto(page, f"{PORTAL}/identifiers/list/applicationGroup")
        if a.identifier in body(page):
            log(f"{a.identifier} already exists")
            return
        goto(page, f"{PORTAL}/identifiers/applicationGroup/add/")
        page.locator("#description").fill(a.description)
        page.locator("#identifier").fill(a.identifier)
        if a.dry_run:
            log("dry run: App Group form filled, not registered")
            return
        button(page, "Continue")
        time.sleep(2)
        button(page, "Register")
        if not wait_for_text(page, re.escape(a.identifier), 20):
            die("registration not confirmed")
        log(f"registered {a.identifier}")


def assign_group(a) -> None:
    """Enable App Groups on a bundle ID and tick the group. The capability can be
    switched on via the API (bundleIdCapabilities APP_GROUPS); choosing which
    group cannot."""
    with tab("developer.apple.com") as page:
        goto(page, f"{PORTAL}/identifiers/list")
        # Rows are clickable divs, not links.
        clicked = page.evaluate(
            """(id) => { const cell = Array.from(document.querySelectorAll('[role=cell] *, [role=cell]'))
                 .find(e => e.children.length === 0 && e.textContent.trim() === id);
               const row = cell && cell.closest('[role=row]'); if (row) row.click(); return !!row; }""",
            a.bundle_id,
        )
        if not clicked:
            die(f"bundle ID {a.bundle_id} not in the identifiers list (register it via the API first)")
        deadline = time.time() + 20
        while time.time() < deadline and "/bundleId/edit/" not in page.url:
            time.sleep(0.5)
        href = page.url
        if not wait_for_text(page, r"Enabled App Groups|App Groups\s+Configure", 30):
            die(f"capabilities did not load on {href}")
        time.sleep(1)
        opened = page.evaluate(
            """() => { const rows = Array.from(document.querySelectorAll('*'))
                 .filter(e => e.children.length < 8 && /^\\s*App Groups\\s*$/.test(e.textContent));
               let p = rows[0]; if (!p) return 'no-row';
               for (let i = 0; i < 6 && p; i++) {
                 const b = p.querySelector && Array.from(p.querySelectorAll('button')).find(x => /Configure|Edit/.test(x.textContent));
                 if (b) { b.click(); return 'opened'; }
                 p = p.parentElement; }
               return 'no-button'; }""")
        if opened != "opened":
            die(f"App Groups capability not enabled on {a.bundle_id} ({opened}); enable it via the API "
                "(POST /v1/bundleIdCapabilities capabilityType APP_GROUPS) and rerun")
        time.sleep(2)
        ticked = page.evaluate(
            """(id) => { const cells = Array.from(document.querySelectorAll('*'))
                 .filter(e => e.children.length === 0 && e.textContent.trim() === id);
               let p = cells[cells.length - 1];
               for (let i = 0; i < 6 && p; i++) { const c = p.querySelector && p.querySelector('input[type=checkbox]');
                 if (c) { if (!c.checked) c.click(); return c.checked; } p = p.parentElement; }
               return false; }""",
            a.group,
        )
        if not ticked:
            die(f"group {a.group} not offered; register it first")
        page.evaluate("""() => { const b = Array.from(document.querySelectorAll('button'))
            .filter(x => x.textContent.trim() === 'Continue' && x.offsetParent); b[b.length - 1].click(); }""")
        time.sleep(2)
        if a.dry_run:
            log(f"dry run: {a.group} ticked for {a.bundle_id}, not saved")
            return
        button(page, "Save")
        time.sleep(2)
        if has_button(page, "Confirm"):
            button(page, "Confirm")  # existing profiles for this ID become invalid
        time.sleep(4)
        goto(page, href, settle=7)
        match = re.search(r"Enabled App Groups \((\d+)\)", body(page))
        log(f"{a.bundle_id}: enabled App Groups = {match.group(1) if match else '?'}; regenerate its profiles")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="fill every form but save nothing")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("create-app")
    p.add_argument("--name", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--sku", required=True)
    p.add_argument("--locale", default="English (U.S.)", help="primary language as shown")
    p.add_argument("--platform", default="IOS", choices=["IOS", "MAC_OS", "TV_OS", "VISION_OS"])
    p.set_defaults(run=create_app)

    p = sub.add_parser("privacy-not-collected")
    p.add_argument("--app", required=True, help="App Store Connect Apple ID of the app")
    p.set_defaults(run=privacy_not_collected)

    p = sub.add_parser("app-group")
    p.add_argument("--identifier", required=True)
    p.add_argument("--description", required=True, help="letters, numbers and spaces only")
    p.set_defaults(run=app_group)

    p = sub.add_parser("assign-group")
    p.add_argument("--bundle-id", required=True, help="identifier, e.g. com.example.app")
    p.add_argument("--group", required=True)
    p.set_defaults(run=assign_group)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
