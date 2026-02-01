# project_spec/progress — Daily Engineering Progress Logs (FleetPrompt)

This folder contains **daily, append-only engineering progress logs** for the `fleetprompt.com` implementation effort.

- These logs are **non-normative** (they do not define requirements).
- The **normative spec** remains `project_spec/spec_v1/` (especially `00_MASTER_SPEC.md`, `10_API_CONTRACTS.md`, and ADRs in `spec_v1/adr/`).
- The purpose is to document **what changed**, **why**, and **what’s next**, day-by-day, in a way that’s easy to audit and review.

If a progress log conflicts with `project_spec/spec_v1/`, the spec wins.

---

## Folder structure

- `progress/README.md` — this index + conventions (you are here)
- `progress/YYYY-MM-DD.md` — one file per day (UTC date recommended)

Recommended: create a new file for each day you do meaningful work, even if it’s short.

---

## Naming convention

Daily logs MUST be named:

- `YYYY-MM-DD.md`

Examples:
- `2026-01-31.md`
- `2026-02-01.md`

---

## Writing rules (conventions)

### 1) Append-only
- Do **not** rewrite history.
- If you need to correct something from a prior day, add a note in today’s log under **Corrections**.

### 2) Traceability and scope
Each daily log SHOULD include:
- what you shipped (high-level)
- key decisions (with references to ADRs/spec sections)
- files/dirs touched (short list)
- what’s still missing / follow-ups
- known issues or risks
- validation performed (typecheck/tests/manual steps)

### 3) Keep it implementation-focused
Prefer:
- “Implemented `/v1/internal/install/redeem` request verification and token single-use semantics”
over:
- “Worked on install stuff”

### 4) Reference portfolio boundaries explicitly (FleetPrompt-specific)
FleetPrompt is Layer 5 (marketplace/distribution). Daily logs SHOULD call out when you touched anything related to:
- **reference-first boundary** (ADR-0001)
- **install intents/tokens handoff** (ADR-0002)
- **server-to-server redemption auth** (must be HMAC raw-bytes + timestamp/nonce window, per v1 decision)

### 5) No secrets
Never include:
- API keys, tokens, credentials
- raw install tokens
- private URLs containing secrets
- sensitive user data

Use placeholders:
- `FLEETPROMPT_INTERNAL_REDEEM_SECRET=***`
- `installToken=***`

---

## Daily log template

Copy/paste this into a new `YYYY-MM-DD.md` file:

---

# YYYY-MM-DD — Progress Log (FleetPrompt)

## Summary (1–3 bullets)
- …
- …

## Spec/ADR alignment notes
- ✅ Implemented: (reference relevant doc sections / ADRs)
- ⚠️ Deviations: (explain why; plan to reconcile)
- ❓ Open questions discovered: (link to spec “Open questions” if applicable)

## What shipped today
### Marketplace / Listings
- …

### Install intents + tokens
- …

### Internal redemption (server-to-server)
- …

## API / Contracts
- Added/changed endpoints:
  - …
- Notes on error envelopes / idempotency / auth:
  - …

## Data model / migrations
- Schema changes:
  - …
- Invariants enforced:
  - …

## Security & tenancy
- Tenant isolation checks:
  - …
- Confused-deputy prevention:
  - …
- Token semantics (expiry, single-use, revocation):
  - …

## Observability
- Key logs/metrics added:
  - …
- Audit trails updated:
  - …

## Files touched (high-level)
- `...`
- `...`

## Validation performed
- Local run steps:
  - …
- Typecheck/tests:
  - …

## Known issues / risks
- …

## Next steps
- [ ] …
- [ ] …

## Corrections (if needed)
- …

---

## Optional manual index

If you want this README to also act as an index, keep an “Index” section updated manually:

### Index
- `YYYY-MM-DD.md` — short title

(Keeping it manual is fine; automation can come later if needed.)