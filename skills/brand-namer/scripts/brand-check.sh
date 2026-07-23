#!/usr/bin/env bash
# brand-check.sh — sweep name availability across domains, npm, PyPI, GitHub org.
# Part of the brand-namer skill. Heuristic; confirm the finalist at a registrar.
#
# Usage:
#   brand-check.sh farka furra forgesmith
#   brand-check.sh --tlds ".com .ai .io" farka
#   brand-check.sh --no-pkg farka furra
#   brand-check.sh --json farka > out.json
#
# Flags:
#   --tlds "<list>"  space-separated TLDs (default: com ai io dev app co sh)
#   --no-pkg         skip npm / PyPI / GitHub org checks
#   --json           emit JSON instead of tables
set -u

TLDS="com ai io dev app co sh"
DO_PKG=1
JSON=0
NAMES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --tlds)   TLDS="$2"; shift 2 ;;
    --no-pkg) DO_PKG=0; shift ;;
    --json)   JSON=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) NAMES+=("$1"); shift ;;
  esac
done

if [ "${#NAMES[@]}" -eq 0 ]; then
  echo "usage: brand-check.sh [--tlds \"com ai io\"] [--no-pkg] [--json] <name>..." >&2
  exit 2
fi

command -v whois >/dev/null 2>&1 || { echo "whois not found (brew install whois)" >&2; exit 1; }

# --- domain availability via WHOIS -----------------------------------------
# Returns: available | taken | unknown
domain_status() {
  local d="$1" out
  out=$(whois "$d" 2>/dev/null)
  if [ -z "$out" ]; then echo "unknown"; return; fi
  # "available" signals (registry-specific wording covered broadly)
  if echo "$out" | grep -qiE "no match|not found|no data found|no object found|^available|status:[[:space:]]*(free|available)|domain not found|not been registered|no entries found"; then
    echo "available"; return
  fi
  # "taken" signals
  if echo "$out" | grep -qiE "creation date|created[[:space:]]*:|registrar:|registry expiry|expiry date|expiration date|domain status:[[:space:]]*(ok|active|client|server)|name server|nserver"; then
    echo "taken"; return
  fi
  echo "unknown"
}

# --- DNS second-opinion (NXDOMAIN hint) ------------------------------------
dns_registered() {
  local d="$1" ns soa
  ns=$(dig +short NS "$d" @1.1.1.1 2>/dev/null | head -1)
  soa=$(dig +short SOA "$d" @1.1.1.1 2>/dev/null | head -1)
  [ -n "$ns" ] || [ -n "$soa" ]
}

# --- package registries -----------------------------------------------------
npm_status() {  # available | taken | unknown
  local n="$1" code
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://registry.npmjs.org/$n" --max-time 8)
  case "$code" in 404) echo available ;; 200) echo taken ;; *) echo unknown ;; esac
}
pypi_status() {
  local n="$1" code
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://pypi.org/pypi/$n/json" --max-time 8)
  case "$code" in 404) echo available ;; 200) echo taken ;; *) echo unknown ;; esac
}
github_org_status() {
  local n="$1" code
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://github.com/$n" --max-time 8)
  case "$code" in 404) echo available ;; 200) echo taken ;; *) echo unknown ;; esac
}

mark() { case "$1" in available) echo "✅ available";; taken) echo "❌ taken";; *) echo "❓ unknown";; esac; }

# --- JSON output ------------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
  printf '{\n  "names": [\n'
  first_n=1
  for name in "${NAMES[@]}"; do
    lname=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    [ $first_n -eq 1 ] || printf ',\n'; first_n=0
    printf '    {\n      "name": "%s",\n      "domains": {' "$lname"
    first_d=1
    for tld in $TLDS; do
      st=$(domain_status "$lname.$tld")
      [ $first_d -eq 1 ] || printf ','; first_d=0
      printf '\n        "%s": "%s"' "$tld" "$st"
    done
    printf '\n      }'
    if [ "$DO_PKG" -eq 1 ]; then
      printf ',\n      "npm": "%s",\n      "pypi": "%s",\n      "github_org": "%s"' \
        "$(npm_status "$lname")" "$(pypi_status "$lname")" "$(github_org_status "$lname")"
    fi
    printf '\n    }'
  done
  printf '\n  ]\n}\n'
  exit 0
fi

# --- table output -----------------------------------------------------------
for name in "${NAMES[@]}"; do
  lname=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  echo ""
  echo "══ $lname ═════════════════════════════════════════"
  echo "  DOMAINS"
  for tld in $TLDS; do
    d="$lname.$tld"
    st=$(domain_status "$d")
    note=""
    # cross-check "available" WHOIS against DNS; warn if DNS says otherwise
    if [ "$st" = "available" ] && dns_registered "$d"; then
      note="  (⚠ DNS records exist — verify at registrar)"
    fi
    printf "    %-22s %s%s\n" "$d" "$(mark "$st")" "$note"
  done
  if [ "$DO_PKG" -eq 1 ]; then
    echo "  PACKAGES / HANDLE"
    printf "    %-22s %s\n" "npm:$lname"        "$(mark "$(npm_status "$lname")")"
    printf "    %-22s %s\n" "pypi:$lname"       "$(mark "$(pypi_status "$lname")")"
    printf "    %-22s %s\n" "github.com/$lname" "$(mark "$(github_org_status "$lname")")"
  fi
done

echo ""
echo "Heuristic sweep. Confirm the finalist at a registrar, then run a trademark"
echo "check (USPTO / EUIPO / WIPO) before committing — see SKILL.md step 5."
