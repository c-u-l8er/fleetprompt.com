# FleetPrompt v1 — Spec-to-Implementation Realignment Plan
Version: 1.0  
Status: Actionable checklist  
Audience: Engineering  
Last updated: 2026-01-31

This document is a **spec-to-implementation realignment checklist** for FleetPrompt v1. Use it to prevent drift between:
- `spec_v1/00_MASTER_SPEC.md` (behavior, flows, acceptance criteria)
- `spec_v1/10_API_CONTRACTS.md` (wire contracts, normalized errors, idempotency)
- `spec_v1/30_DATA_MODEL_CONVEX.md` (tables, indexes, invariants, access control)
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` (threat model, UGC safety, token safety)
- `spec_v1/60_TESTING_ACCEPTANCE.md` (tests + release gates)

If you find contradictions:
1. `00_MASTER_SPEC.md` wins for system behavior.
2. ADRs win for invariants and rationale.
3. API/data model must be updated to match the above, not the other way around.

---

## 0) One-time decisions to lock (to prevent drift)

### D0.1 Canonical ID strategy (portfolio-shared)
Decide and document:
- Do you expose Convex IDs directly as API IDs (stringified `_id`), or do you introduce prefixed IDs (`lst_...`, `rel_...`)?
- How do you represent “cursor” values (opaque string derived from `(createdAtMs, _id)` recommended)?

**Acceptance**
- Every endpoint and every persisted record uses the same identifier strategy.
- Pagination cursors are opaque and stable.

### D0.2 IDOR strategy: NOT_FOUND vs UNAUTHORIZED (portfolio-consistency)
Choose one and apply everywhere (recommended: `NOT_FOUND` for cross-tenant ids).

**Acceptance**
- Every “get by id” endpoint behaves consistently:
  - if caller does not own/see resource ⇒ `NOT_FOUND` (recommended)
  - never leaks existence via different shapes/status codes.

### D0.3 Server-to-server auth scheme for `/v1/internal/install/redeem`
Pick exactly one and implement consistently:
- HMAC signature over raw bytes + timestamp window (recommended; aligns with portfolio patterns), OR
- mTLS, OR
- short-lived service JWT with strict issuer/audience and key rotation

**Acceptance**
- Internal endpoints cannot be called from browsers.
- Replay protection exists at least via timestamp skew window.
- Secrets are never logged.

### D0.4 Artifact hosting stance (v1)
Decide:
- FleetPrompt hosts artifacts (object storage + signed URLs), OR
- FleetPrompt stores only artifact pointers and fulfillment is handled by SpecPrompt, OR
- Both (must be explicit per release artifact)

**Acceptance**
- `Release.artifacts[].download.mode` semantics are consistent across API and implementation.
- No endpoint accidentally exposes raw artifact content if you chose “pointers only”.

---

## 1) Canonical invariants (must remain true)

### 1.1 Reference-first, not copies (hard rule)
FleetPrompt MUST store only references + bounded summaries. It MUST NOT store:
- WHS telemetry streams
- Agentromatic execution logs
- Agentelic room transcripts/messages

**Acceptance**
- Search the schema and confirm no table is designed to hold upstream logs/telemetry/transcripts.

### 1.2 Install is a handoff, not a side effect (hard rule)
- FleetPrompt may create install intents and mint tokens.
- FleetPrompt redemption resolves intent + references only.
- The target system performs install/import and re-checks authorization.

**Acceptance**
- Redeem endpoint does not call WHS/Agentromatic/Agentelic to perform installs.

### 1.3 Tokens are short-lived, revocable, and (preferably) single-use
- Store token hashes (preferred) or opaque lookup ids (never raw tokens at rest).
- Enforce expiry.
- Enforce single-use or deterministic redemption semantics.

**Acceptance**
- Token replay tests pass; token values do not appear in logs.

### 1.4 Releases are append-only; revocation is a state transition
- Publishing a release creates an immutable record.
- Revoking changes status; do not delete.

**Acceptance**
- Release history remains auditable; publisher can see revoked releases; public visibility policy is consistent.

### 1.5 Idempotency is mandatory for retryable writes
Retryable writes MUST accept `Idempotency-Key` and dedupe by scope:
- listing create
- listing status change
- release publish
- release revoke
- install intent create
- install token issuance
- internal redeem (idempotent redemption behavior)

**Acceptance**
- Same key + same payload returns same result; same key + different payload returns `CONFLICT`.

---

## 2) Spec alignment matrix (what must match across docs)

### 2.1 Enums and statuses
Ensure these are consistent across `00_MASTER_SPEC.md`, `10_API_CONTRACTS.md`, and `30_DATA_MODEL_CONVEX.md`:

- ListingStatus: `draft | published | unlisted | suspended`
- AssetKind: `whs_agent | agentromatic_workflow | spec_asset` (spec_asset may be unimplemented but must not break validation rules)
- ReleaseStatus: `published | revoked`
- InstallTargetSystem: `whs | agentromatic | agentelic`
- InstallIntentStatus: `created | token_issued | redeemed | expired | canceled`

**Acceptance**
- You can copy/paste enum lists between docs without edits.
- Implementation uses the same exact strings.

### 2.2 Public vs private field split
Public endpoints MUST NOT return:
- moderation flags/reasons
- private publisher notes
- install intents/tokens
- any internal auth/debug metadata

**Acceptance**
- There is a documented “public shape” and it is enforced server-side.

### 2.3 Release reference constraints by AssetKind
Rules must match across docs and implementation:
- `whs_agent` ⇒ `refs.whsAgentId` REQUIRED
- `agentromatic_workflow` ⇒ `refs.agentromaticWorkflowId` REQUIRED
- `spec_asset` ⇒ `refs.specAssetId` REQUIRED (only if supported)

`whsDeploymentId` is a hint only; never authoritative.

**Acceptance**
- Publishing a release with missing required ref fails with `VALIDATION_FAILED`.
- Publishing with extra irrelevant refs is either rejected or ignored consistently (pick one).

---

## 3) Data model realignment checklist (Convex)

> Target doc: `spec_v1/30_DATA_MODEL_CONVEX.md`

### 3.1 Users
- [ ] `users.externalId` unique mapping exists.
- [ ] Single helper resolves current user and is used everywhere (no drift).
- [ ] Optional publisher/admin flags are stored in one canonical place (users table or publisher profile table).

**Acceptance**
- Every auth-required function begins by resolving `users._id`.

### 3.2 Listings
- [ ] Listing schema matches API fields and size limits.
- [ ] `publisherUserId` owner field exists and is immutable.
- [ ] Public listings are `status="published"` only.
- [ ] Publishing requires at least one published release (enforce at publish time).

**Acceptance**
- No endpoint can return a draft listing to a public caller.

### 3.3 Releases
- [ ] Releases table exists and is append-only aside from status transitions.
- [ ] Enforce `(listingId, version)` uniqueness by lookup-before-insert.
- [ ] Denormalize `publisherUserId` on release (recommended) for fast auth checks.
- [ ] Public policy for revoked releases is explicit and consistent.

**Acceptance**
- Duplicate version publish fails deterministically (`CONFLICT`).
- Revoked releases are not installable.

### 3.4 Install intents and tokens
- [ ] `installIntents` are buyer-scoped and IDOR-safe.
- [ ] `installTokens` are stored hashed (recommended) with TTL, status, and single-use behavior.
- [ ] Issuing a new token invalidates prior token(s) if that is the chosen policy (documented).
- [ ] Token redemption lookup uses hash index.

**Acceptance**
- Token replay does not succeed.
- No raw token is persisted.

### 3.5 Idempotency ledger
- [ ] `idempotencyKeys` (or equivalent) exists and is used by all retryable writes.
- [ ] Stores:
  - request hash
  - minimal response payload or response reference
  - TTL cleanup plan

**Acceptance**
- Idempotency works under concurrent requests (no duplicate listings/releases/intents).

### 3.6 Audit log (recommended baseline)
- [ ] Append-only `auditLog` exists.
- [ ] Every mutation writes an audit event (listing/release/install intent/token/mod actions).
- [ ] Audit records are bounded and secret-free.

**Acceptance**
- You can answer “who changed what and when?” for security incidents.

---

## 4) API realignment checklist (contracts → handlers)

> Target doc: `spec_v1/10_API_CONTRACTS.md`

### 4.1 Normalized errors
- [ ] Every error response uses the canonical envelope.
- [ ] Stable `code` strings are used consistently.
- [ ] `requestId` is always included.
- [ ] Validation failures include `details.fields[]`.

**Acceptance**
- A contract test suite validates error envelope shape for representative endpoints.

### 4.2 Pagination
- [ ] All list endpoints accept `cursor` and `limit`.
- [ ] Enforce max limit (recommended 200).
- [ ] `nextCursor` is `null` when there are no more items.

**Acceptance**
- Pagination does not return duplicates in steady state.

### 4.3 Public endpoints
- [ ] `GET /v1/public/listings/search` returns only published listings.
- [ ] `GET /v1/public/listings/:listingId` returns NOT_FOUND for non-published listings.
- [ ] Rate limiting exists.

**Acceptance**
- Public response never includes private fields (moderation, internal notes).

### 4.4 Publisher endpoints
- [ ] All publisher mutations require publisher role/capability.
- [ ] Ownership enforced on every listing/release mutation.
- [ ] Idempotency keys required for create/publish/revoke/status changes.

**Acceptance**
- Cross-publisher write attempts behave as NOT_FOUND (recommended).

### 4.5 Install handoff endpoints
- [ ] Buyer can create install intent and mint token.
- [ ] Token TTL is bounded.
- [ ] Redeem endpoint is server-to-server only and returns intent + release refs.

**Acceptance**
- Browser cannot call redeem endpoint successfully.
- Redeem endpoint does not leak token existence (recommended: NOT_FOUND on invalid tokens).

---

## 5) Security realignment checklist (implementation-grade)

> Target docs: `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`, plus API constraints

### 5.1 UGC safety (mandatory)
- [ ] Markdown sanitized; raw HTML disallowed.
- [ ] Link policy enforced (`https:` only recommended).
- [ ] External links include `rel="noopener noreferrer nofollow"`.
- [ ] Image policy is explicit (recommended: no SVG in v1).

**Acceptance**
- Stored XSS suite passes in UI and API render tests.

### 5.2 Confused deputy protections (mandatory)
- [ ] Internal endpoints require server-to-server auth.
- [ ] Internal endpoints reject browser-originated access (do not rely solely on CORS).
- [ ] Redeem resolves intent only; no upstream side effects.

**Acceptance**
- Security tests prove internal endpoints cannot be used to trigger installs from browser context.

### 5.3 Secrets and token leakage prevention
- [ ] No raw tokens logged or stored.
- [ ] Logs redact common secret patterns.
- [ ] Error envelopes do not include sensitive details.

**Acceptance**
- Log scanning tests demonstrate absence of token-like values.

### 5.4 Abuse controls
- [ ] Rate limits on public search/browse and on write endpoints.
- [ ] Cursor pagination limits enforced.
- [ ] Optional bot mitigation at edge documented.

**Acceptance**
- Abuse tests show rate limit behavior triggers as expected.

---

## 6) Implementation sequencing (recommended order)

1. **Lock decisions D0.1–D0.4** (write ADRs where needed).
2. **Implement identity mapping + authz helpers** (centralize ownership checks).
3. **Implement listings + releases data model + invariants**.
4. **Implement public read endpoints + safe rendering**.
5. **Implement publisher console endpoints + idempotency**.
6. **Implement install intents + token issuance + redemption seam**.
7. **Add audit log coverage** (every mutation emits an event).
8. **Add tests per `60_TESTING_ACCEPTANCE.md` and make them gating**.

---

## 7) Spec patch procedure (when drift is found)

When code and spec disagree:

1. **Security/tenant isolation drift**
   - Fix code first to match spec.
   - Add tests to prevent regression.
2. **Naming/shape drift (no semantic change)**
   - Prefer updating docs to match established code if it’s already shipped, but keep semantics unchanged.
3. **Semantic drift (behavior change)**
   - Write an ADR capturing the decision.
   - Update `00_MASTER_SPEC.md`, `10_API_CONTRACTS.md`, and `30_DATA_MODEL_CONVEX.md` together.
   - Update tests.

Never leave the system in a half-and-half state where API and data model disagree.

---

## 8) Release gates (realignment complete when…)
FleetPrompt is considered “realigned” when:

- [ ] All normative docs agree:
  - `00_MASTER_SPEC.md`
  - `10_API_CONTRACTS.md`
  - `30_DATA_MODEL_CONVEX.md`
  - `40_SECURITY_SECRETS_COMPLIANCE.md`
  - `60_TESTING_ACCEPTANCE.md`
- [ ] Idempotency works on all retryable write endpoints.
- [ ] Public endpoints expose only published content and are rate-limited.
- [ ] Internal redemption is server-to-server only and safe.
- [ ] IDOR suite passes across publisher and buyer resources.
- [ ] XSS suite passes for listing descriptions and release notes.
- [ ] Token replay tests pass (expiry + single-use + revocation).
- [ ] Audit log coverage exists for all mutations (recommended baseline).

---

## 9) Known “watch points” (easy places to drift)
1. Public vs publisher shapes accidentally sharing serializers (private fields leaking).
2. Release refs validation not matching AssetKind constraints.
3. Token storage/logging regressions (raw token appears in logs).
4. Redemption endpoint being called by browser due to misconfigured auth/CORS.
5. Inconsistent error codes across endpoints (breaks UI).
6. Pagination cursors not stable (duplicates under concurrent inserts).
7. “Spec asset” becoming half-implemented and breaking validation paths.

---

## 10) Outputs you should produce from this plan
Once you start implementation work, you should be able to point to:

- A single shared `authz` module used by all endpoints:
  - resolve user, enforce ownership, enforce role flags
- A single idempotency helper used by all retryable writes
- A single markdown sanitization/render policy used everywhere
- A test suite that maps directly to `spec_v1/60_TESTING_ACCEPTANCE.md`
- A staging proof that internal redemption works server-to-server without side effects

---