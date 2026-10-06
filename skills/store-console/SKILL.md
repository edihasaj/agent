---
name: store-console
description: Do the Google Play Console and App Store Connect steps that their official APIs cannot do, by driving the signed-in agent Chrome — create the app record on either store, Play's App content declarations (content rating, target audience, ads, sign-in, advertising ID, government, financial, health), Play's accessibility and foreground-service permission declarations, Play store category, country availability and "Send changes for review", App Store "Data Not Collected" privacy answers, and Apple App Group registration and assignment. Use when publishing or updating an Android or iOS app and one of these steps is next. Everything else (builds, listings, screenshots, pricing, submission) goes through the official APIs.
---

# store-console

Fills the store-console forms that have no public API. Each command has a
`--dry-run` that fills the form, screenshots it to `/tmp/store-console-last.png`
and saves nothing. Dry-run first on any app that is live or in review.

## Use the API first

| Step | Google Play | App Store Connect |
|---|---|---|
| Create the app record | **this skill** | **this skill** (`apps` does not allow CREATE) |
| Upload build, tracks, releases | API (`edits.bundles`, `edits.tracks`, `edits.commit`) | `altool`/`xcodebuild -exportArchive`, then `appStoreVersions` + `reviewSubmissions` |
| Listing text, images, screenshots | API (`edits.listings`, `edits.images`) | API (`appStoreVersionLocalizations`, `appScreenshots`) |
| Contact email / website | API (`edits.details`) | API (`appStoreReviewDetails`, localizations) |
| Category | **this skill** | API (`appInfos` relationships) |
| Data safety / App Privacy | API (`applications.dataSafety`, CSV) | **this skill** (Data Not Collected only) |
| Content rating / age rating | **this skill** | API (`ageRatingDeclarations`) |
| Target audience, ads, sign-in, ad ID, government, financial, health | **this skill** | — |
| Accessibility and foreground-service declarations | **this skill** | — |
| Country availability | **this skill** (API is read-only) | API (`/v2/appAvailabilities`) |
| Price | API (in-app products only; app price at create) | API (`appPriceSchedules`) |
| Bundle IDs, capabilities, certificates, profiles | — | API (`bundleIds`, `bundleIdCapabilities`, `certificates`, `profiles`) |
| App Group register / assign to an ID | — | **this skill** |
| Send for review | API commit sends edit changes; **this skill** for console-made changes | API (`reviewSubmissions` `submitted: true`) |

Play's API needs a service account added in Play Console > Users and
permissions; without one, upload the bundle and listing in the console too.
App Store Connect API calls use the `Apple Admin API Key` (see the
`apple-codesign` skill for how it is stored).

## Setup

```bash
~/Projects/abx/scripts/chrome-agent start      # dedicated agent Chrome on :9223
S=~/Projects/agent/skills/store-console/scripts/store-console
```

A person signs in to Play Console and App Store Connect in that Chrome once
(Apple asks for 2FA). The commands stop with exit code 3 when a session has
expired. They never type passwords.

## Google Play

The developer id and app id are the numbers in the console URL
(`/developers/<developer>/app/<app>/`).

```bash
$S play --developer D create-app --name "Name: Subtitle" --package com.example.app   # free app
$S play --developer D --dry-run declarations --app A \
   --privacy-url https://example.com/privacy --rating-email you@example.com \
   --no-restricted-content --ages "18 and over"
$S play --developer D permissions --app A \
   --accessibility-video https://example.com/review/demo.mp4 \
   --fgs NETWORK_OTHER BACKGROUND_AUDIO_IN --fgs-video https://example.com/review/demo.mp4
$S play --developer D category --app A --category Productivity
$S play --developer D countries --app A            # every country on production
$S play --developer D send-for-review --app A
```

- `create-app` ticks the Developer Program Policies and US export-law boxes;
  run it only when the owner asked to create the app.
- `declarations` answers **No** to every content-rating question and declares
  no ads, no sign-in, no advertising ID, not a government, financial or health
  app. `--no-restricted-content` is required to confirm that is true. Apps
  with user content, ads, accounts or under-13 audiences need those forms done
  by hand.
- `permissions` needs a video of the in-app prominent disclosure and of each
  foreground-service task. Record it on an emulator with
  `adb shell screenrecord`, stop it with `adb shell pkill -INT screenrecord`
  (killing the host `adb` leaves an unplayable file), compress with ffmpeg and
  host it on the app's site. Foreground-service reasons are the console's ids:
  `NETWORK_BACKUP NETWORK_OTHER LOCAL_MEDIA_TRANSCODE LOCAL_IMPORT_EXPORT
  LOCAL_OTHER DATA_SYNC_OTHER BACKGROUND_AUDIO_IN MICROPHONE_OTHER`; any
  "Other" also needs `--fgs-description`.
- The release review page lists missing declarations as links; run
  `permissions` for those, then save the release and `send-for-review`.
- Phone screenshots must be at most 2:1 (1080×2400 is rejected; use 1080×1920).

## App Store Connect and developer portal

```bash
$S asc create-app --name "Name" --bundle-id com.example.app --sku example-ios
$S asc privacy-not-collected --app 1234567890      # App Privacy: Data Not Collected, published
$S asc app-group --identifier group.com.example.app --description "Example shared"
$S asc assign-group --bundle-id com.example.app --group group.com.example.app
```

- Register the bundle ID with the API first; `create-app` only offers
  registered IDs.
- `assign-group` needs the App Groups capability on the ID; switch it on with
  `POST /v1/bundleIdCapabilities` (`capabilityType: APP_GROUPS`). Assigning a
  group invalidates that ID's provisioning profiles; recreate them with the API.
- `privacy-not-collected` is only correct when the app collects nothing
  (no analytics, crash reporting, accounts or tracking). Otherwise answer the
  privacy questions by hand.

## When a person is needed

Stop and report, don't guess, when a command exits 3 (signed out), when a form
asks something these commands do not cover, or when Google or Apple show a new
agreement to accept.
