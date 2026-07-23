---
name: brand-namer
description: >
  Generate and vet a product/company name from context: coin candidates across
  metaphor buckets and multiple languages (English, Latin/Greek, Albanian, etc.),
  score each on metaphor fit + sayability + cross-language slur/collision safety,
  then sweep availability (domains via WHOIS/DNS, npm/PyPI, GitHub org) and flag
  trademark-conflict risk. Use when Edi asks to rename a project, find a brandable
  name, "find a name we can get a domain for", or check if a name is taken.
---

# Brand Namer (Edi)

Turn a product's *context* into a ranked shortlist of names that are meaningful,
sayable, safe across languages, and actually **acquirable** (domain + package +
handle + trademark-clear). Built from the kiln→Farka session.

## Workflow

### 1. Extract context (what is it, what's the transformation?)
Read the repo/README. Pin down:
- **What it does** in one line.
- **The core transformation** (input → output). Names should encode this metaphor.
  - e.g. Kiln = supervised fine-tuning of small models = *raw data + heat/compute → a hardened, specialized model*. Metaphor family: fire / forge / refining ore.
- **Audience** (devs? consumers?) → sets tone (terse/technical vs warm).

### 2. Generate candidates across buckets AND languages
Don't just brainstorm English. Pull from:
- **English metaphor words** (forge, smelt, temper, ingot, bellows, crucible, hearth…).
- **Latin / Greek roots** (often brandable + international).
- **Albanian** (Edi's — quietly personal, frequently free domains): fire/forge set = `farka` (the forge), `furra` (the kiln — literal), `prush` (embers), `flaka` (flame), `ndez` (ignite), `zjarr` (fire), `farkëtoj` (to forge/shape).
- **Coined/compound** as last resort (`-kit`/`-lab`/`-hq` read as "side project" — deprioritize).
Aim for 15–25 raw candidates before filtering.

### 3. Score each (rubric — 0–5 per axis)
| Axis | What it measures |
|---|---|
| **Metaphor fit** | Does the name encode the input→output transformation? |
| **Sayability** | One look → correct pronunciation. Digraphs (`sh`, `zj`), double letters, silent letters cost points. |
| **Safety** ⛔ | Cross-language slur / crude echo / negative meaning. This is a **hard gate**, not a score: any real collision = disqualified. (Kill example: `anneal` reads as "anal".) Check English + major languages (ES/FR/DE/IT/PT + Albanian). When unsure, WebSearch `"<name>" meaning slang`. |
| **Availability** | `.com`/`.ai`/`.io` + npm/PyPI + GitHub org open? (run the script — step 4) |
| **Distinctiveness** | Coinable & trademark-able? Generic/descriptive words are weak marks and hard to defend. |

Reject on Safety first, then rank by the sum of the rest. Note *why* the top pick wins.

### 4. Sweep availability (automated)
```sh
skills/brand-namer/scripts/brand-check.sh farka furra forgesmith smeltery
```
Checks per name: domains (`.com .ai .io .dev .app .co .sh`) via WHOIS, npm, PyPI,
GitHub org. Output is a per-name table. WHOIS/DNS is a **heuristic** — confirm the
finalist at the registrar before buying. Flags: `--tlds ".com .ai .io"`,
`--no-pkg` (skip npm/PyPI/GitHub), `--json`.

### 5. Trademark / rights conflict (manual, judgment call)
Domain-free ≠ legally clear. For the finalist, check for confusingly similar
marks in the same class (software/SaaS):
- **USPTO** (US): https://tmsearch.uspto.gov/  → search the wordmark.
- **EUIPO** (EU): https://euipo.europa.eu/eSearch/  (eSearch+).
- **WIPO Global Brand DB** (worldwide): https://branddb.wipo.int/.
- Also: exact-name company on Google + Crunchbase, and existing **prominent OSS
  project** of the same name (naming collision hurts discoverability even without
  a TM — e.g. "Kiln" already = a Chroma fine-tuning tool + a Fog Creek git product).
Report as **risk level** (clear / minor collision / conflict), not legal advice.
Recommend a proper counsel/TM search before filing.

### 6. Output
A scored shortlist table + a one-line "grab X now" recommendation, and offer the
next step: register + wire DNS via the **[[domain-dns-ops]]** skill (Cloudflare /
DNSimple / Namecheap under `~/Projects/manager`).

## Notes
- **Availability heuristics differ from truth.** WHOIS "no match" is strong; DNS
  NXDOMAIN is weaker (registered-but-unconfigured domains exist). Always confirm
  the winner at a registrar.
- **`.com` for real dictionary words is ~always gone.** Steer to `.ai`/`.io`, a
  less-common word, or a coined term.
- **Personal-but-portable wins**: an Albanian word nobody outside needs the
  backstory for (Farka) beats a generic English compound.
- Hand off registration to `domain-dns-ops`; this skill stops at "confirmed
  buyable + rights-risk noted".
