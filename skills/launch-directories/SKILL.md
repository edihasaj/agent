---
name: launch-directories
description: Fill and submit an app's listing on a launch site or directory (Product Hunt, Show HN, BetaList, Uneed, Microlaunch, SaaSHub, AlternativeTo, DevHunt, Peerlist) for a Compass launch. Claims the launch, fills the form in the dedicated agent Chrome with the owner's approved copy and images, sends a screenshot, and presses the final submit only when Compass says the owner chose Submit now. Use when Compass or Edi asks to fill, continue, or submit a launch-site submission.
---

# Launch-site submissions

Compass owns the copy and every decision. One run fills or submits one site for
one launch, reports to Compass, and stops.

## Rules

- One launch, one site per run. Never touch another site, listing, or account.
- Use only the packet's values, link, and images. Do not rewrite the copy. If a
  required form field has no value, ask (see "When a person is needed").
- Press the site's final submit, launch, or publish button only when the claimed
  packet's `launch.action` is `submit`. With `fill`, stop before that button.
- Never pay or open a checkout. Choose free options only. Never solve or bypass a
  CAPTCHA. Never create accounts, verify emails, enter passwords, or accept terms.
- Report every stop to Compass, then end the run. Never wait in a loop for a person;
  Compass starts a new run when the owner decides.

## Setup

```bash
~/Projects/abx/scripts/chrome-agent start
export ABX_LIVE_CDP_URL=http://127.0.0.1:9223
L="$COMPASS_URL/api/marketing/launches/<id>"
W="/tmp/launch-<id>" && mkdir -p "$W"
```

`COMPASS_URL` and the launch id come from the prompt. The agent Chrome keeps its
own signed-in sessions, separate from Edi's daily Chrome. Live tab ids,
`upload`, `select`, `wait`, and `screenshot --full` need abx 0.1.13 or later; if
a command is unsupported, run `brew upgrade abx` once, then report a problem if
it is still missing.

## 1. Claim

```bash
curl -fsS -X POST "$L/claim" -o "$W/packet.json" || exit 0
```

A failed claim means another run has it or the copy changed since approval: stop
without reporting. Read `launch.action`, `launch.tab`, `site` (name, url, how,
fields with limits), `values`, `link`, `assets`, and `rules`.

## 2. Open the form

If `launch.tab` is set, an earlier run left the form open: `abx live tab
<launch.tab>` switches to it. Otherwise, or when abx says no open tab has that
id, open the site in a new tab with `abx live newtab "<site.url>"`. Both print
the tab's id, and every later `abx live` command acts on that tab while it stays
open, so other tabs in the agent Chrome never get in the way. Send the id as
`"tab"` in every report, so the next run continues in the same tab.

Run `abx live snapshot`. If the site shows a sign-in wall, report `login`. Follow
the site note below to reach the submission form.

In a `submit` run, first compare the form's values with the packet. If they
differ, or the earlier tab was gone, fill again with the same packet (or open the
site's saved draft) before submitting.

## 3. Fill

- Map each packet value to the form field with the same meaning. Use
  `abx live fill <selector> <text>`, `abx live select <selector> <value>`, and
  `abx live click`. Prefer selectors built from labels, names, or placeholders.
- `link` is the product URL for every URL field. Do not change it.
- Images: download each asset, then upload it to the matching input.

  ```bash
  curl -fsS "$COMPASS_URL<asset.url>" -o "$W/<asset.filename>"
  abx live upload 'input[type=file]' "$W/<asset.filename>"
  ```

  Use `assets.logo` for logo or thumbnail inputs and `assets.gallery`, in order,
  for screenshots.
- Read the values back with `abx live js` and compare them with the packet. Fix
  any difference before going on.

## 4. Stop or submit

With `fill`, take the evidence and ask for confirmation:

```bash
abx live screenshot --full "$W/filled.png"
curl -fsS -X PUT --data-binary @"$W/filled.png" -H 'Content-Type: image/png' "$L/evidence"
curl -fsS -X POST "$L/report" -H 'Content-Type: application/json' \
  -d '{"status":"needs_you","waiting_for":"confirm","tab":"<tab id>","detail":"Filled every field and uploaded 3 images."}'
```

With `submit`, press the final button once, wait for the confirmation page, take a
full-page screenshot, upload it as evidence, and report:

```bash
curl -fsS -X POST "$L/report" -H 'Content-Type: application/json' \
  -d '{"status":"submitted","tab":"<tab id>","url":"<listing or confirmation URL>","detail":"Submitted. The site reviews new listings."}'
```

Report `live` instead of `submitted` when the listing is already public. Then
close the tab with `abx live closetab`.

## When a person is needed

Report `needs_you` with one `waiting_for` value and a one-sentence `question`,
upload a screenshot when it helps, then stop:

| waiting_for | When |
| --- | --- |
| `login` | Signed out. Ask Edi to sign in to the site in the agent Chrome window. |
| `signup` | The site needs an account first. |
| `captcha` | Any CAPTCHA or human check. |
| `payment` | The next step costs money, or only paid options remain. |
| `question` | A required field or choice has no packet value, such as a launch date or category. |
| `problem` | The site errors, the form changed beyond recognition, or a tool fails. |

## Site notes

Forms change; read the page before acting.

- **Product Hunt**: submit from `/posts/new`. The flow has several steps and keeps
  a draft after the first one; in a `submit` run, continue that draft rather than
  starting a new product. Topics come from its suggestions. Ask for the launch date.
- **Show HN**: `/submit` with title, URL (the packet link), and optional text.
  No images. After submitting, the item URL is `/item?id=...`; report `live`.
- **BetaList**: `/submit`. Choose the free queue, never paid expedite.
- **Uneed**: `/submit-a-tool` reads the website first. Replace the scraped name,
  tagline, and description with packet values. Choose the free queue.
- **Microlaunch**: sign in, then open the launch form from the header.
- **SaaSHub**: `/submit`. Listings are reviewed and verified later; report `submitted`.
- **AlternativeTo**: user menu, Suggest new application. Use the packet's platforms,
  pricing, and alternatives.
- **DevHunt**: GitHub sign-in. Ask which launch week to pick.
- **Peerlist**: needs a Peerlist profile; launches are weekly.
