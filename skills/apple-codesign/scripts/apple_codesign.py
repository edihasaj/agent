# /// script
# requires-python = ">=3.10"
# dependencies = ["cryptography>=42", "pyjwt>=2.8", "requests>=2.31"]
# ///
"""apple-codesign — one CLI to issue Apple certs, sign, notarize and staple any
macOS app, driven by an App Store Connect API key kept in 1Password.

Design goal (Edi): never spin up signing per app. Set the team up once, then every
app is: `apple-codesign run MyApp.app` → signed, notarized, stapled.

What the API key CAN do (fully automated here):
  • issue Apple Development / Distribution, Mac App Distribution,
    Mac Installer Distribution, Mac Development, Pass Type ID certs
  • notarize + staple anything (notarytool)
What it CANNOT do (Apple policy — Account-Holder identity only, no API key holds it):
  • create a DEVELOPER_ID_APPLICATION cert  → 403 FORBIDDEN
    Handled the fastlane-match way: create once, stash .p12 in 1Password, reuse forever.

Credentials are resolved in this order:
  1. env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8)
  2. 1Password item (op://$OP_VAULT/Apple Admin API Key) with fields
     "Key ID" + "Issuer ID" and an attached file AuthKey_<KeyID>.p8
     Set OP_VAULT (e.g. in ~/.profile) or pass --vault to pick the vault.

Examples:
  apple-codesign whoami
  apple-codesign issue MAC_APP_DISTRIBUTION --stash
  apple-codesign devid               # status / one-time-creation guidance
  apple-codesign setup               # pull cert + notary key from 1Password → this machine
  apple-codesign sign dist/MyApp.app
  apple-codesign notarize dist/MyApp.dmg
  apple-codesign run  dist/MyApp.app # sign → notarize → staple, end to end
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import plistlib
import secrets
import shutil
import subprocess
import sys
import tempfile

import jwt
import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"

# certificateType values the App Store Connect API accepts. DEVELOPER_ID_* are
# listed for completeness but Apple rejects their creation with 403 (see devid()).
CERT_TYPES = {
    "DEVELOPMENT", "DISTRIBUTION",
    "IOS_DEVELOPMENT", "IOS_DISTRIBUTION",
    "MAC_APP_DISTRIBUTION", "MAC_INSTALLER_DISTRIBUTION", "MAC_APP_DEVELOPMENT",
    "DEVELOPER_ID_APPLICATION", "DEVELOPER_ID_KEXT",
    "PASS_TYPE_ID", "PASS_TYPE_ID_WITH_NFC",
}
ACCOUNT_HOLDER_ONLY = {"DEVELOPER_ID_APPLICATION", "DEVELOPER_ID_KEXT"}

DEFAULT_VAULT = os.environ.get("OP_VAULT", "Private")  # set OP_VAULT (e.g. ~/.profile) to your vault
DEFAULT_API_ITEM = os.environ.get("OP_API_ITEM", "Apple Admin API Key")
DEFAULT_CERT_ITEM = os.environ.get("OP_CERT_ITEM", "Apple Developer ID Application")
DEFAULT_PROFILE = os.environ.get("NOTARY_PROFILE", "asc-notary")
DEFAULT_KEYCHAIN = os.environ.get(
    "SIGNING_KEYCHAIN", os.path.expanduser("~/Library/Keychains/apple-codesign.keychain-db"))
INTERMEDIATE_CA = "https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"


# ── small utils ──────────────────────────────────────────────────────────────
def die(msg: str, code: int = 1):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg: str):
    print(f"→ {msg}")


def ok(msg: str):
    print(f"✓ {msg}")


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, text=True, capture_output=True, **kw)


def op_read(ref: str, out_file: str | None = None) -> str | None:
    """Read a single field/file from 1Password. Targeted by design (CLAUDE.md)."""
    if not shutil.which("op"):
        die("1Password CLI `op` not found and credential not in env")
    cmd = ["op", "read", ref]
    if out_file:
        cmd += ["--out-file", out_file, "--force"]
    r = run(cmd)
    if r.returncode != 0:
        return None
    return r.stdout.strip() if not out_file else out_file


# ── credentials ──────────────────────────────────────────────────────────────
def resolve_api_key(vault: str, item: str) -> tuple[str, str, str]:
    """Return (key_id, issuer_id, p8_path). Env first, then 1Password."""
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    p8 = os.environ.get("ASC_KEY_PATH")
    if key_id and issuer and p8 and os.path.isfile(os.path.expanduser(p8)):
        return key_id, issuer, os.path.expanduser(p8)

    info(f"resolving API key from 1Password (op://{vault}/{item})…")
    key_id = key_id or op_read(f"op://{vault}/{item}/Key ID")
    issuer = issuer or op_read(f"op://{vault}/{item}/Issuer ID")
    if not key_id or not issuer:
        die("could not resolve Key ID / Issuer ID (set ASC_KEY_ID + ASC_ISSUER_ID or fix 1Password item)")
    p8 = os.path.join(tempfile.mkdtemp(prefix="asc"), f"AuthKey_{key_id}.p8")
    if not op_read(f"op://{vault}/{item}/AuthKey_{key_id}.p8", out_file=p8):
        die(f"could not read AuthKey_{key_id}.p8 from 1Password item '{item}'")
    return key_id, issuer, p8


def make_token(key_id: str, issuer: str, p8_path: str) -> str:
    with open(p8_path, "rb") as f:
        private = f.read()
    now = dt.datetime.now(dt.timezone.utc)
    return jwt.encode(
        {"iss": issuer, "iat": int(now.timestamp()),
         "exp": int((now + dt.timedelta(minutes=18)).timestamp()),
         "aud": "appstoreconnect-v1"},
        private, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )


def asc(method: str, path: str, token: str, **kw) -> requests.Response:
    headers = {"Authorization": f"Bearer {token}"}
    return requests.request(method, f"{API}{path}", headers=headers, timeout=30, **kw)


# ── commands ─────────────────────────────────────────────────────────────────
def cmd_whoami(a):
    key_id, issuer, p8 = resolve_api_key(a.vault, a.api_item)
    token = make_token(key_id, issuer, p8)
    r = asc("GET", "/certificates?limit=200", token)
    if r.status_code != 200:
        die(f"API {r.status_code}: {r.text}")
    certs = r.json().get("data", [])
    ok(f"key {key_id} authenticated (issuer {issuer[:8]}…)")
    print(f"  {len(certs)} certificate(s) on the team:")
    seen: dict[str, int] = {}
    for c in certs:
        t = c["attributes"]["certificateType"]
        seen[t] = seen.get(t, 0) + 1
    for t, n in sorted(seen.items()):
        flag = "  ⟵ Account-Holder-only (cannot API-create)" if t in ACCOUNT_HOLDER_ONLY else ""
        print(f"    {n:>2}× {t}{flag}")
    has_devid = any(c["attributes"]["certificateType"] == "DEVELOPER_ID_APPLICATION" for c in certs)
    print(f"\n  Developer ID Application present: {'yes ✓' if has_devid else 'no ✗ (create once — see `devid`)'}")


def _make_csr(common_name: str) -> tuple[rsa.RSAPrivateKey, str]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)]))
           .sign(key, hashes.SHA256()))
    return key, csr.public_bytes(serialization.Encoding.PEM).decode()


def _write_p12(key, cert, label: str, out: str) -> str:
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    password = secrets.token_urlsafe(18)
    blob = pkcs12.serialize_key_and_certificates(
        name=label.encode(), key=key, cert=cert, cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(password.encode()))
    with open(out, "wb") as f:
        f.write(blob)
    return password


def cmd_issue(a):
    ctype = a.type.upper()
    if ctype not in CERT_TYPES:
        die(f"unknown certificate type '{ctype}'. One of: {', '.join(sorted(CERT_TYPES))}")
    key_id, issuer, p8 = resolve_api_key(a.vault, a.api_item)
    token = make_token(key_id, issuer, p8)

    key, csr_pem = _make_csr(a.cn or f"{ctype} {key_id}")
    body = {"data": {"type": "certificates",
                     "attributes": {"certificateType": ctype, "csrContent": csr_pem}}}
    info(f"requesting {ctype} certificate…")
    r = asc("POST", "/certificates", token, json=body)
    if r.status_code not in (200, 201):
        detail = ""
        try:
            detail = r.json()["errors"][0].get("detail", "")
        except Exception:
            detail = r.text
        if r.status_code == 403 and ctype in ACCOUNT_HOLDER_ONLY:
            die(f"403 — {ctype} can only be created by the Account Holder; no API key qualifies.\n"
                f"  Run `apple-codesign devid` for the one-time creation + reuse path.")
        die(f"API {r.status_code}: {detail}")

    content = r.json()["data"]["attributes"]["certificateContent"]
    cert = x509.load_der_x509_certificate(base64.b64decode(content))
    ok(f"issued {ctype}: {cert.subject.rfc4514_string()}  exp {cert.not_valid_after_utc:%Y-%m-%d}")

    out = a.out or f"dist/{ctype.lower()}.p12"
    pw = _write_p12(key, cert, ctype, out)
    ok(f"wrote {out}")
    if a.stash:
        _stash_p12(a.vault, f"{ctype} cert", out, pw)
    else:
        print(f"P12_PASSWORD={pw}")


def _stash_p12(vault: str, item: str, p12_path: str, password: str):
    """Create/update a 1Password item holding the .p12 + its password."""
    info(f"stashing into 1Password (op://{vault}/{item})…")
    r = run(["op", "item", "get", item, "--vault", vault])
    exists = r.returncode == 0
    if exists:
        run(["op", "item", "edit", item, "--vault", vault, f"password={password}"])
        run(["op", "document", "edit", item, p12_path, "--vault", vault])
    else:
        run(["op", "document", "create", p12_path, "--title", item,
             "--vault", vault, "--file-name", os.path.basename(p12_path)])
        run(["op", "item", "edit", item, "--vault", vault, f"password[password]={password}"])
    ok(f"stored {item} in vault {vault}")


def cmd_devid(a):
    """Status + the one-time creation guidance for Developer ID Application."""
    key_id, issuer, p8 = resolve_api_key(a.vault, a.api_item)
    token = make_token(key_id, issuer, p8)
    r = asc("GET", "/certificates?limit=200", token)
    certs = r.json().get("data", []) if r.status_code == 200 else []
    have = [c for c in certs if c["attributes"]["certificateType"] == "DEVELOPER_ID_APPLICATION"]
    if have:
        ok(f"team already has {len(have)} Developer ID Application cert(s):")
        for c in have:
            at = c["attributes"]
            print(f"    {at.get('name','?')}  exp {at.get('expirationDate','?')}")
        print("\n  → If this machine can't sign yet, run `apple-codesign setup` to import the .p12 from 1Password.")
        return
    print(
        "No Developer ID Application certificate exists for the team yet.\n"
        "Apple permits its creation ONLY by the Account Holder — no API key qualifies (verified 403).\n"
        "Create it ONCE (≈30s), then it's reused forever by every app + machine + CI.\n\n"
        "Fastest path (recommended):\n"
        "  Xcode ▸ Settings ▸ Accounts ▸ <team> ▸ Manage Certificates ▸ + ▸ Developer ID Application\n\n"
        "Then make it reusable (this stores it in 1Password for all future apps):\n"
        "  1. Keychain Access ▸ login ▸ your new 'Developer ID Application' ▸ right-click ▸ Export ▸ .p12 (set a password)\n"
        f"  2. apple-codesign stash-devid <file>.p12   # → op://{a.vault}/{DEFAULT_CERT_ITEM}\n\n"
        "After that: `apple-codesign run MyApp.app` works on any machine via `setup`.")


def cmd_stash_devid(a):
    if not os.path.isfile(a.p12):
        die(f"not found: {a.p12}")
    pw = a.password or os.environ.get("P12_PASSWORD")
    if not pw:
        pw = input("p12 password: ").strip()
    # normalise the stored filename so `setup` can find it.
    dest = os.path.join(tempfile.mkdtemp(), "developer-id.p12")
    shutil.copy(a.p12, dest)
    _stash_p12(a.vault, a.cert_item, dest, pw)


def _add_to_search_list(kc: str):
    """Prepend the dedicated keychain to the user search list (keeping the rest)."""
    cur = run(["security", "list-keychains", "-d", "user"]).stdout
    paths = [ln.strip().strip('"') for ln in cur.splitlines() if ln.strip()]
    if kc not in paths:
        run(["security", "list-keychains", "-d", "user", "-s", kc, *paths])


def cmd_setup(a):
    """Pull the Developer ID cert + notary key from 1Password into a dedicated,
    fully-controlled signing keychain (headless-safe — never touches login)."""
    kc = a.keychain
    info("importing Developer ID certificate from 1Password…")
    p12 = os.path.join(tempfile.mkdtemp(), "developer-id.p12")
    if not op_read(f"op://{a.vault}/{a.cert_item}/developer-id.p12", out_file=p12):
        die(f"no developer-id.p12 in op://{a.vault}/{a.cert_item} — create + stash it first (`devid`)")
    pw = op_read(f"op://{a.vault}/{a.cert_item}/password") or ""

    # Dedicated keychain, unlocked with the p12 password (strong, fetchable, reproducible).
    # Reset each run so it's idempotent and never accumulates stale keys.
    run(["security", "delete-keychain", kc])  # ignore if absent
    c = run(["security", "create-keychain", "-p", pw, kc])
    if c.returncode != 0:
        die(f"create-keychain failed: {c.stderr.strip()}")
    run(["security", "set-keychain-settings", kc])          # no auto-lock timeout
    run(["security", "unlock-keychain", "-p", pw, kc])

    intermediate = os.path.join(tempfile.gettempdir(), "DeveloperIDG2CA.cer")
    try:
        with requests.get(INTERMEDIATE_CA, timeout=15) as resp:
            open(intermediate, "wb").write(resp.content)
        run(["security", "import", intermediate, "-k", kc])
    except Exception:
        pass
    imp = run(["security", "import", p12, "-k", kc, "-P", pw,
               "-A", "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
    if imp.returncode != 0:
        die(f"keychain import failed: {imp.stderr.strip()}")
    # let codesign use the private key non-interactively
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", pw, kc])
    _add_to_search_list(kc)

    info("storing notary API key…")
    key_id, issuer, p8 = resolve_api_key(a.vault, a.api_item)
    sc = run(["xcrun", "notarytool", "store-credentials", a.profile,
              "--key", p8, "--key-id", key_id, "--issuer", issuer, "--keychain", kc])
    if sc.returncode != 0:
        die(f"notarytool store-credentials failed: {sc.stderr.strip()}")

    found = _find_identity(kc)
    if found:
        ok(f"ready — identity '{found[1]}', notary profile '{a.profile}', keychain {os.path.basename(kc)}")
    else:
        die("Developer ID identity not found after import")


def _find_identity(keychain: str | None = None) -> tuple[str, str] | None:
    """Return (sha1, name) of a Developer ID Application identity. When `keychain`
    is given, search only it — and return the SHA-1 so signing is unambiguous even
    if other keychains hold an identically-named cert."""
    cmd = ["security", "find-identity", "-v", "-p", "codesigning"]
    if keychain:
        cmd.append(keychain)
    for line in run(cmd).stdout.splitlines():
        if "Developer ID Application" in line and '"' in line:
            # '  1) <SHA1> "Developer ID Application: Name (TEAMID)"'
            parts = line.split()
            sha1 = parts[1] if len(parts) > 1 else ""
            return sha1, line.split('"')[1]
    return None


def _clean_entitlements(target: str) -> str | None:
    """Dump the target's entitlements, strip the debug-only get-task-allow (which
    Apple rejects at notarization), and return a temp plist path — or None if there
    are no entitlements to preserve."""
    r = run(["codesign", "-d", "--entitlements", "-", "--xml", target])
    raw = (r.stdout or "").encode()
    idx = raw.find(b"<?xml")
    if idx == -1:
        return None
    try:
        ent = plistlib.loads(raw[idx:])
    except Exception:
        return None
    if not ent:
        return None
    ent.pop("com.apple.security.get-task-allow", None)
    out = os.path.join(tempfile.mkdtemp(), "entitlements.plist")
    with open(out, "wb") as f:
        plistlib.dump(ent, f)
    return out


def cmd_sign(a):
    if a.identity:
        ident, label = a.identity, a.identity
    else:
        found = _find_identity(getattr(a, "keychain", None))
        if not found:
            die("no Developer ID Application identity found — run `setup`")
        ident, label = found  # sign by SHA-1 → unambiguous across keychains
    target = a.path
    if not os.path.exists(target):
        die(f"not found: {target}")
    info(f"codesign (hardened runtime) → {target}  [{label}]")
    cmd = ["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", ident]
    if a.deep:  # legacy nested signing — discouraged, opt-in only
        cmd.append("--deep")
    ent = a.entitlements or _clean_entitlements(target)
    if ent:
        cmd += ["--entitlements", ent]
    cmd.append(target)
    r = run(cmd)
    if r.returncode != 0:
        die(f"codesign failed: {r.stderr.strip()}")
    v = run(["codesign", "--verify", "--strict", "--verbose=2", target])
    ok(f"signed + verified: {label}")
    if v.stderr:
        print(v.stderr.strip())


def cmd_notarize(a):
    target = a.path
    if not os.path.exists(target):
        die(f"not found: {target}")
    # notarytool needs a zip/dmg/pkg, not a bare .app
    submit = target
    cleanup = None
    if target.endswith(".app"):
        submit = target[:-4] + ".zip"
        info(f"zipping {target} → {submit}")
        z = run(["ditto", "-c", "-k", "--keepParent", target, submit])
        if z.returncode != 0:
            die(f"ditto zip failed: {z.stderr.strip()}")
        cleanup = submit
    info(f"submitting to notary service (profile {a.profile})…")
    cmd = ["xcrun", "notarytool", "submit", submit, "--keychain-profile", a.profile,
           "--wait", "--output-format", "json"]
    if getattr(a, "keychain", None):
        cmd += ["--keychain", a.keychain]
    r = run(cmd)
    try:
        result = json.loads(r.stdout)
    except Exception:
        die(f"could not parse notarytool output: {r.stdout or r.stderr}")
    sid, status = result.get("id"), result.get("status")
    if status != "Accepted":
        # notarytool exits 0 even when the verdict is Invalid — surface Apple's reasons.
        if sid:
            log = run(["xcrun", "notarytool", "log", sid, "--keychain-profile", a.profile]
                      + (["--keychain", a.keychain] if getattr(a, "keychain", None) else []))
            print(log.stdout.strip()[:4000])
        if cleanup and os.path.exists(cleanup):
            os.remove(cleanup)
        die(f"notarization {status} (id {sid})")
    ok(f"notarization Accepted (id {sid})")
    # staple the original artifact (.app/.dmg/.pkg), never the throwaway zip
    if cleanup and os.path.exists(cleanup):
        os.remove(cleanup)
    s = run(["xcrun", "stapler", "staple", target])
    if s.returncode == 0:
        ok(f"notarized + stapled: {target}")
    else:
        print(f"⚠ stapled failed ({s.stderr.strip()}) — re-run `stapler staple {target}`")


def cmd_run(a):
    """Full pipeline: sign → notarize → staple."""
    cmd_sign(a)
    cmd_notarize(a)
    # gatekeeper assessment for a final sanity check
    r = run(["spctl", "--assess", "--type", "execute", "--verbose=2", a.path])
    out = (r.stderr or r.stdout).strip()
    print(out)
    if "accepted" in out:
        ok("Gatekeeper: accepted ✓")


# ── argparse ─────────────────────────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="apple-codesign", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--vault", default=DEFAULT_VAULT, help=f"1Password vault (default {DEFAULT_VAULT})")
    p.add_argument("--api-item", default=DEFAULT_API_ITEM, help="1Password API-key item")
    p.add_argument("--cert-item", default=DEFAULT_CERT_ITEM, help="1Password Developer ID cert item")
    p.add_argument("--profile", default=DEFAULT_PROFILE, help="notarytool keychain profile")
    p.add_argument("--keychain", default=DEFAULT_KEYCHAIN,
                   help="dedicated signing keychain (created by `setup`; never the login keychain)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("whoami", help="authenticate the API key + list the team's certs").set_defaults(func=cmd_whoami)

    s = sub.add_parser("issue", help="issue an API-creatable cert → .p12")
    s.add_argument("type", help="cert type, e.g. MAC_APP_DISTRIBUTION")
    s.add_argument("--cn", help="CSR common name")
    s.add_argument("--out", help="output .p12 path")
    s.add_argument("--stash", action="store_true", help="store the .p12 + password in 1Password")
    s.set_defaults(func=cmd_issue)

    sub.add_parser("devid", help="Developer ID cert status + one-time-creation guidance").set_defaults(func=cmd_devid)

    s = sub.add_parser("stash-devid", help="store an exported Developer ID .p12 in 1Password")
    s.add_argument("p12")
    s.add_argument("--password", help="p12 password (or env P12_PASSWORD / prompt)")
    s.set_defaults(func=cmd_stash_devid)

    sub.add_parser("setup", help="import cert + notary key from 1Password onto this machine").set_defaults(func=cmd_setup)

    s = sub.add_parser("sign", help="codesign an app with hardened runtime")
    s.add_argument("path")
    s.add_argument("--identity", help="signing identity (default: auto-detect Developer ID)")
    s.add_argument("--entitlements", help="entitlements plist")
    s.add_argument("--deep", action="store_true", help="use --deep (legacy nested signing)")
    s.set_defaults(func=cmd_sign)

    s = sub.add_parser("notarize", help="notarize + staple an app/dmg/pkg/zip")
    s.add_argument("path")
    s.set_defaults(func=cmd_notarize)

    s = sub.add_parser("run", help="sign → notarize → staple, end to end")
    s.add_argument("path")
    s.add_argument("--identity")
    s.add_argument("--entitlements")
    s.add_argument("--deep", action="store_true")
    s.set_defaults(func=cmd_run)
    return p


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except KeyboardInterrupt:
        die("interrupted", 130)


if __name__ == "__main__":
    main()
