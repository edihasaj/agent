"""Play Console steps the Google Play Developer API cannot do.

Covered: create the app, the App content declarations (privacy policy, ads,
sign-in, content rating, target audience, advertising ID, government,
financial, health), sensitive permission declarations (accessibility,
foreground services), the store category, country availability (the API's
countryavailability is read-only) and "Send changes for review".

Listings, images, contact details, bundles, tracks and the Data safety form
have official API methods — use those instead.
"""

from __future__ import annotations

import argparse
import re
import time

from console_common import (
    answer_no_to_all,
    body,
    button,
    choose,
    die,
    fill_label,
    goto,
    has_button,
    log,
    save_or_discard,
    tab,
    wait_for_text,
)

HOST = "play.google.com"


def console(developer: str) -> str:
    return f"https://play.google.com/console/u/0/developers/{developer}"


def app_url(a, path: str) -> str:
    return f"{console(a.developer)}/app/{a.app}/{path}"


# --- create -------------------------------------------------------------------

def create_app(a) -> None:
    with tab(HOST) as page:
        goto(page, f"{console(a.developer)}/create-new-app")
        fill_label(page, "App name", a.name)
        fill_label(page, "App package name", a.package)
        choose(page, debug_id="game-radio" if a.game else "app-radio")
        choose(page, debug_id="paid-radio" if a.paid else "free-radio")
        if a.language:
            log(f"note: default language left as shown; change it in the form if it is not {a.language}")
        # Developer Program Policies + US export laws.
        page.evaluate(
            """() => document.querySelectorAll('input[type=checkbox]').forEach(c => {
                 if (c.offsetParent !== null && !c.checked) c.click(); })"""
        )
        page.screenshot(path="/tmp/store-console-last.png")
        if a.dry_run:
            log("dry run: create-app form filled, not created (screenshot /tmp/store-console-last.png)")
            goto(page, f"{console(a.developer)}/app-list", settle=2)
            return
        button(page, "Create app")
        deadline = time.time() + 60
        while time.time() < deadline and "/app/" not in page.url:
            time.sleep(1)
        match = re.search(r"/app/(\d+)/", page.url)
        if not match:
            die(f"app not created; still on {page.url}: {body(page)[:300]}")
        log(f"created app {match.group(1)}")


# --- App content declarations -------------------------------------------------

def declarations(a) -> None:
    if not a.no_restricted_content:
        die("the content-rating step answers 'No' to every content question; pass "
            "--no-restricted-content to confirm that is true for this app, or fill it by hand")
    with tab(HOST) as page:
        if a.privacy_url:
            goto(page, app_url(a, "app-content/privacy-policy"))
            fill_label(page, "Privacy policy URL", a.privacy_url)
            save_or_discard(page, a.dry_run)

        goto(page, app_url(a, "app-content/ads-declaration"))
        choose(page, r"^No, my app does not contain ads" if not a.ads else r"^Yes, my app contains ads")
        save_or_discard(page, a.dry_run)

        goto(page, app_url(a, "app-content/testing-credentials"))
        choose(page, r"^No\b")  # nothing behind a sign-in; otherwise fill by hand
        save_or_discard(page, a.dry_run)

        content_rating(page, a)
        target_audience(page, a)

        goto(page, app_url(a, "app-content/ad-id-declaration"))
        choose(page, r"^No$")
        save_or_discard(page, a.dry_run)

        goto(page, app_url(a, "app-content/government-apps"))
        choose(page, debug_id="no-radio")
        save_or_discard(page, a.dry_run)

        goto(page, app_url(a, "app-content/finance"))
        choose(page, debug_id="POLICY_RESPONSE_CHOICE_ID_FINANCE_NONE")
        two_step_save(page, a.dry_run)

        goto(page, app_url(a, "app-content/health"))
        choose(page, debug_id="POLICY_RESPONSE_CHOICE_ID_NOT_HEALTH_APP")
        two_step_save(page, a.dry_run)


def two_step_save(page, dry_run: bool) -> None:
    """Forms with a Next page before Save (financial, health)."""
    if dry_run:
        save_or_discard(page, True)
        return
    button(page, "Next")
    time.sleep(2)
    save_or_discard(page, False)


def content_rating(page, a) -> None:
    goto(page, app_url(a, "app-content/content-rating-overview"))
    if has_button(page, "Start questionnaire"):
        button(page, "Start questionnaire")
    elif has_button(page, "Start new questionnaire"):
        button(page, "Start new questionnaire")
    else:
        log("content rating: questionnaire already submitted; skipping (use the console to change it)")
        return
    time.sleep(4)
    page.locator("input[type=email]").first.fill(a.rating_email)
    choose(page, r"^All Other App Types")
    choose(page, r"^I agree to the Terms of Use")
    button(page, "Next")
    time.sleep(3)
    for _ in range(6):
        answered = answer_no_to_all(page)
        for line in answered:
            log(f"  rating {line}")
        if any(line.startswith("UNANSWERED") for line in answered):
            die("a content-rating question has no 'No' option; finish it by hand")
        if not answered:
            break
        time.sleep(1.5)
    if a.dry_run:
        log("dry run: rating answers filled; leaving the questionnaire unsubmitted")
        page.screenshot(path="/tmp/store-console-last.png")
        return
    button(page, "Save")
    wait_for_text(page, r"Questionnaire saved")
    button(page, "Next")
    time.sleep(4)
    log("content rating summary: " + " | ".join(
        l for l in body(page).splitlines() if re.search(r"Everyone|PEGI|USK|ClassInd|IARC|\b\d+\+", l))[:300])
    button(page, "Save")
    wait_for_text(page, r"Your current ratings|applied", 30)
    log("content rating applied")


def target_audience(page, a) -> None:
    goto(page, app_url(a, "app-content/target-audience-content"))
    for band in a.ages:
        choose(page, f"^{re.escape(band)}$")
    if a.dry_run:
        save_or_discard(page, True)
        return
    # Under-13 bands open extra pages (appeal to children, ads); those need a person.
    for _ in range(5):
        if has_button(page, "Save") and not has_button(page, "Next"):
            break
        button(page, "Next")
        time.sleep(3)
    save_or_discard(page, False)


# --- Sensitive permissions ----------------------------------------------------

FGS_REASONS = {
    "NETWORK_BACKUP", "NETWORK_OTHER", "LOCAL_MEDIA_TRANSCODE", "LOCAL_IMPORT_EXPORT",
    "LOCAL_OTHER", "DATA_SYNC_OTHER", "BACKGROUND_AUDIO_IN", "MICROPHONE_OTHER",
}


def permissions(a) -> None:
    with tab(HOST) as page:
        if a.accessibility_video:
            goto(page, app_url(a, "app-content/accessibility-permissions"))
            choose(page, r"^App functionality")
            radios = page.locator("material-radio", has_text=re.compile(r"^No$"))
            radios.last.locator("input").click()  # no sensitive data via the API
            page.locator("input[type=url]").first.fill(a.accessibility_video)
            choose(page, debug_id="video-disclosure-agreement-checkbox")
            save_or_discard(page, a.dry_run)

        if a.fgs:
            if not a.fgs_video:
                die("--fgs needs --fgs-video")
            goto(page, app_url(a, "app-content/foreground-services"))
            for reason in a.fgs:
                if reason not in FGS_REASONS:
                    die(f"unknown --fgs reason {reason}; one of {sorted(FGS_REASONS)}")
                choose(page, debug_id=f"POLICY_RESPONSE_CHOICE_ID_FGS_REASON_{reason}_CHECKBOX")
            time.sleep(1)
            # Only the boxes just ticked reveal their fields; hidden ones must stay empty.
            links = page.get_by_label("Video link")
            for i in range(links.count()):
                if links.nth(i).is_visible():
                    links.nth(i).fill(a.fgs_video)
            notes = page.get_by_label("Describe permission use")
            for i in range(notes.count()):
                if notes.nth(i).is_visible():
                    if not a.fgs_description:
                        die("an 'Other' reason needs --fgs-description")
                    notes.nth(i).fill(a.fgs_description)
            save_or_discard(page, a.dry_run)


# --- Store settings, countries, review ---------------------------------------

def category(a) -> None:
    with tab(HOST) as page:
        goto(page, app_url(a, "store-settings"))
        page.get_by_role("button", name="Edit", exact=True).first.click()
        time.sleep(2)
        page.locator("[debug-id=category-dropdown] dropdown-button").click()
        time.sleep(1)
        picked = page.evaluate(
            """(name) => { const item = Array.from(document.querySelectorAll('material-select-dropdown-item, [role=option]'))
                 .find(e => e.offsetParent && e.textContent.trim() === name);
               if (item) item.click(); return !!item; }""",
            a.category,
        )
        if not picked:
            die(f"category '{a.category}' not offered")
        time.sleep(1)
        save_or_discard(page, a.dry_run)


def countries(a) -> None:
    with tab(HOST) as page:
        goto(page, app_url(a, f"tracks/{a.track}?tab=countryAvailability"))
        if has_button(page, "Add countries / regions"):
            button(page, "Add countries / regions")
        elif has_button(page, "Edit countries / regions"):
            button(page, "Edit countries / regions")
        time.sleep(3)
        header = page.get_by_role("checkbox").first
        if not header.is_checked():
            header.click()
        time.sleep(2)
        if a.dry_run:
            log("dry run: every country ticked, not saved")
            page.screenshot(path="/tmp/store-console-last.png")
            if has_button(page, "Discard"):
                button(page, "Discard")
            return
        button(page, "Save")
        time.sleep(5)
        match = re.search(r"Targeted \((\d+)\)", body(page))
        log(f"countries targeted: {match.group(1) if match else 'unknown — check the page'}")


def send_for_review(a) -> None:
    with tab(HOST) as page:
        goto(page, app_url(a, "publishing"), settle=8)
        text = body(page)
        match = re.search(r"(Submit|Send) (\d+) changes? for review", text)
        if not match:
            log("nothing waiting to be sent" if "Changes in review" in text else text[:400])
            return
        log(f"pending: {match.group(0)}")
        if a.dry_run:
            log("dry run: not sending")
            return
        button(page, match.group(0))
        time.sleep(2)
        button(page, "Send changes for review")
        if not wait_for_text(page, r"Changes in review|now in review", 30):
            die("send not confirmed; check the Publishing overview")
        log("sent for review (Play runs quick checks first, up to ~15 minutes)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--developer", required=True, help="Play Console developer account id (from the console URL)")
    parser.add_argument("--dry-run", action="store_true", help="fill every form but save nothing")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("create-app")
    p.add_argument("--name", required=True)
    p.add_argument("--package", required=True)
    p.add_argument("--paid", action="store_true")
    p.add_argument("--game", action="store_true")
    p.add_argument("--language")
    p.set_defaults(run=create_app)

    def with_app(p):
        p.add_argument("--app", required=True, help="Play app id (from the console URL)")
        return p

    p = with_app(sub.add_parser("declarations"))
    p.add_argument("--privacy-url")
    p.add_argument("--ads", action="store_true", help="the app shows ads")
    p.add_argument("--rating-email", required=True)
    p.add_argument("--no-restricted-content", action="store_true",
                   help="confirm 'No' is true for every content-rating question")
    p.add_argument("--ages", nargs="+", default=["18 and over"],
                   help='target age bands as shown, e.g. "16-17" "18 and over"')
    p.set_defaults(run=declarations)

    p = with_app(sub.add_parser("permissions"))
    p.add_argument("--accessibility-video", help="link to the prominent-disclosure video")
    p.add_argument("--fgs", nargs="+", help="foreground-service reasons, e.g. NETWORK_OTHER BACKGROUND_AUDIO_IN")
    p.add_argument("--fgs-video")
    p.add_argument("--fgs-description")
    p.set_defaults(run=permissions)

    p = with_app(sub.add_parser("category"))
    p.add_argument("--category", required=True, help='as shown, e.g. "Productivity"')
    p.set_defaults(run=category)

    p = with_app(sub.add_parser("countries"))
    p.add_argument("--track", default="production")
    p.set_defaults(run=countries)

    p = with_app(sub.add_parser("send-for-review"))
    p.set_defaults(run=send_for_review)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
