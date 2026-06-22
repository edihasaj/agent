---
name: apple-codesign
description: >
  Issue Apple certificates, then sign + notarize + staple any macOS app, driven by one
  App Store Connect API key kept in 1Password. Use when distributing a macOS app outside
  the App Store (Developer ID, notarization, Gatekeeper), setting up signing on a new
  machine or CI, or issuing Apple Development/Distribution/Mac App Store certs. Team-wide:
  set up once, reuse for every app — no per-app spin-up.
---

# apple-codesign (Edi)

One CLI for the whole Apple signing chain, app-agnostic. Credentials live in 1Password
(`Apple Admin API Key`); the Developer ID cert is created once and reused. Pick the vault
with `OP_VAULT` (set it in your private `~/.profile`) or `--vault`.

```bash
apple-codesign --help          # via uv launcher (scripts/apple-codesign)
# or directly:
uv run skills/apple-codesign/scripts/apple_codesign.py <cmd>
```

## The one Apple limitation (read this first)

The App Store Connect **API key issues almost every cert** — Apple Development, Apple
Distribution, **Mac App Distribution**, **Mac Installer Distribution**, Mac Development,
Pass Type IDs — all via `apple-codesign issue <TYPE>`.

It **cannot** create a **Developer ID Application** cert (the one needed to notarize a
directly-downloaded `.app`/`.dmg`). Apple restricts that to the **Account Holder
identity**, which no API key can hold → `403 FORBIDDEN`. This is a hard policy (fastlane
hits the same wall). The cert is team-wide and lasts ~5 years, so the standard practice
(and what this skill does) is **create it once, stash the `.p12` in 1Password, reuse
forever**. Only programmatic mint path is the Apple-ID web session (fastlane `spaceship`,
2FA cookie) — not worth the fragility for a once-per-5-years action.

## Golden paths

**First time for the team (once ever):**
```bash
apple-codesign whoami            # confirm key works; see if a Developer ID cert exists
apple-codesign devid             # if none: prints the 30-second Xcode creation steps
# create it in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application
# export it from Keychain Access as .p12, then:
apple-codesign stash-devid ~/Downloads/DeveloperID.p12     # → op://$OP_VAULT/Apple Developer ID Application
```

**Any machine / CI (per machine, once):**
```bash
apple-codesign setup             # pulls cert + notary key from 1Password → keychain + notarytool profile
```

**Every app, every release (the payoff):**
```bash
apple-codesign run dist/MyApp.app        # sign → notarize → staple → Gatekeeper check
# or piecemeal:
apple-codesign sign dist/MyApp.app
apple-codesign notarize dist/MyApp.dmg
```

**Issue App Store / other certs (fully automated):**
```bash
apple-codesign issue MAC_APP_DISTRIBUTION --stash      # .p12 + password saved to 1Password
apple-codesign issue DEVELOPMENT --out dist/dev.p12
```

## Credential resolution

1. Env: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` (.p8) — used if all present.
2. Else 1Password item `op://<vault>/<api-item>/…` with fields **Key ID**, **Issuer ID**
   and attached file **AuthKey_<KeyID>.p8**.

Overrides: `--vault`, `--api-item`, `--cert-item`, `--profile` (or env `OP_VAULT`,
`OP_API_ITEM`, `OP_CERT_ITEM`, `NOTARY_PROFILE`). 1Password access is targeted per
CLAUDE.md (single item/field, no diagnostics).

## Commands

| Command | Does |
| --- | --- |
| `whoami` | Auth the API key; list team certs; flag if Developer ID is missing |
| `issue <TYPE> [--out --cn --stash]` | Generate CSR + request an API-creatable cert → `.p12` |
| `devid` | Developer ID status + one-time creation guidance |
| `stash-devid <p12> [--password]` | Store an exported Developer ID `.p12` in 1Password |
| `setup` | Import cert + notary key from 1Password onto this machine |
| `sign <app> [--identity --entitlements --deep]` | codesign with hardened runtime + verify |
| `notarize <app\|dmg\|pkg\|zip>` | notarytool submit `--wait` + staple |
| `run <app>` | sign → notarize → staple → `spctl` assess |

## CI

`apple-codesign setup` then `apple-codesign run` works in CI if `op` is configured with a
service account (set `OP_SERVICE_ACCOUNT_TOKEN`, always pass `--vault`). Without 1Password,
feed `ASC_*` env + import the Developer ID `.p12` from a base64 secret (see
`~/Projects/ZoomClip/.github/workflows/release.yml` for a self-contained example).

## Notes

- Needs: `uv` (Python deps), `op` (1Password), Xcode CLT (`codesign`, `xcrun notarytool`,
  `stapler`, `spctl`, `security`, `ditto`).
- Never re-signs / changes bundle IDs implicitly — `sign` only attaches a Developer ID
  signature + hardened runtime (TCC-safe).
- `notarize` zips a bare `.app` for submission, then staples the original artifact.
