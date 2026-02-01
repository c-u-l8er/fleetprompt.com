# fleetprompt.com — Testing Plan & Acceptance Criteria (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines the **FleetPrompt v1** testing strategy, required test cases, and the system-level **acceptance criteria** (“definition of done”).

FleetPrompt is **Layer 5 (Marketplace / Distribution)**:
- It is **public-facing** and UGC-heavy → XSS/abuse risks dominate.
- It is **reference-first** → no upstream telemetry/log mirroring.
- It provides **install handoff** via intents + tokens → must not become a confused-deputy proxy.

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Testing philosophy (what we optimize for)

### 1.1 Priorities (in order)
1. **Security correctness**
   - tenant isolation / IDOR safety
   - internal endpoints not callable from browsers
   - install token integrity (expiry, single-use, revocation)
2. **UGC safety**
   - XSS prevention and safe link policy
   - upload safety (if implemented)
3. **Idempotency and replay safety**
   - retryable writes dedupe correctly
   - conflict on same idempotency key with different payload
4. **Core UX correctness**
   - browse/search listings
   - publisher console create/update/publish/revoke flows
   - buyer install intent + token issuance
5. **Resilience and performance guardrails**
   - basic rate limiting behavior
   - stable pagination

### 1.2 “Done” definition for v1
FleetPrompt v1 is “done” when:
- all **MUST** tests in this document pass, and
- the system-level acceptance criteria in §10 pass in staging with realistic traffic constraints.

### 1.3 Test pyramid (recommended)
- **Unit tests:** validation, sanitization helpers, idempotency logic, token lifecycle helpers
- **Integration tests:** API endpoints + DB invariants + authz checks + dedupe behavior
- **E2E tests:** top-to-bottom flows with real auth, public pages, publisher console, and internal redemption (server-to-server)

---

## 2) Environments & prerequisites

### 2.1 Environments
- **Local dev:** fastest iteration for unit + selected integration tests
- **Staging:** required for E2E and internal redemption tests
- **Production:** monitor-only; no destructive tests

### 2.2 Identity prerequisites
- Auth provider must issue a stable subject id (`externalId`).
- Test setup must support at least:
  - `User A (publisher)`
  - `User B (publisher)`
  - `User C (buyer)`
  - `User D (buyer)`

### 2.3 Server-to-server redemption prerequisites
To test `/v1/internal/install/redeem` (or equivalent):
- Staging must be configured with a service auth scheme (e.g., HMAC or mTLS).
- Tests must be able to produce signed/authorized requests (from a test harness, not a browser).

### 2.4 Content safety prerequisites
- Markdown sanitizer is configured and deterministic.
- Link scheme policy is enforced (recommended: `https:` only).
- HTML is disallowed or stripped.

---

## 3) Unit test plan (MUST)

Unit tests should run fast and cover the most security-sensitive logic.

### 3.1 Validators and schema enforcement (MUST)
**Tests:**
- U-VAL-01: Listing `name` length bounds
- U-VAL-02: Listing `summary` length bounds
- U-VAL-03: Listing `descriptionMarkdown` max length and allowed format
- U-VAL-04: Tags/categories limits (count and per-item length)
- U-VAL-05: URL validation rejects:
  - `javascript:` URLs
  - `data:` URLs
  - URLs with control characters
  - overly long URLs
- U-VAL-06: Release `version` bounds + allowed charset
- U-VAL-07: Release `refs` validation matches listing `assetKind`
  - `whs_agent` requires `whsAgentId`
  - `agentromatic_workflow` requires `agentromaticWorkflowId`
  - `spec_asset` requires `specAssetId` (if enabled)

**Expected:**
- failures produce deterministic `VALIDATION_FAILED` with field-level errors.

### 3.2 Markdown sanitization and rendering safety (MUST)
**Tests:**
- U-XSS-01: `<script>alert(1)</script>` is removed/escaped
- U-XSS-02: `<img src=x onerror=alert(1)>` is removed/neutralized
- U-XSS-03: Markdown link with `javascript:` scheme is rejected or rewritten safely
- U-XSS-04: Raw HTML blocks are stripped (if markdown parser supports them)
- U-XSS-05: `rel="noopener noreferrer nofollow"` is applied on outbound links (if rendering layer enforces it)
- U-XSS-06: Markdown is sanitized deterministically (same input → same output)

**Expected:**
- output contains no executable scripts or event handlers.

### 3.3 Idempotency helper behavior (MUST)
Assuming the implementation uses an idempotency ledger or equivalent:
**Tests:**
- U-IDEMP-01: same `(scope, endpoint, key)` + same payload → returns same stored response
- U-IDEMP-02: same key + different payload hash → returns `CONFLICT`
- U-IDEMP-03: keys do not include secrets or large user content (guardrail test: enforce max length and reject if exceeded)

### 3.4 Install token lifecycle helpers (MUST)
**Tests:**
- U-TOK-01: token TTL enforcement (expiresAtMs computed correctly, bounded)
- U-TOK-02: token is treated as secret (never emitted into logs by helpers; if logger injection exists, enforce redaction)
- U-TOK-03: token hashing format stable and deterministic
- U-TOK-04: single-use transition rules:
  - `issued` → `redeemed` is terminal
  - subsequent redemption attempts are rejected
- U-TOK-05: revocation behavior:
  - issuing a new token can revoke old tokens (if this is the chosen policy)

---

## 4) Integration test plan (MUST)

Integration tests exercise endpoint behavior + DB invariants + authz.

### 4.1 Public marketplace reads (MUST)
**Tests:**
- I-PUB-01: `public.listings.search` returns only `published` listings
- I-PUB-02: `public.listings.get` returns `NOT_FOUND` for `draft`/`unlisted` listings
- I-PUB-03: public listing payload does not include private fields:
  - moderation flags/reasons
  - internal notes
  - unpublished releases (if not intended)
- I-PUB-04: public release listing hides revoked releases by default (if that’s the policy)
- I-PUB-05: pagination stability:
  - limit capped (max enforced)
  - `nextCursor` works
  - no duplicates across pages under normal append-only conditions

### 4.2 Publisher console CRUD + authz (MUST)
**Setup:** User A is publisher; User B is publisher.

**Tests:**
- I-PUBC-01: publisher A creates listing (draft)
- I-PUBC-02: publisher A updates listing fields
- I-PUBC-03: publisher A publishes a release for listing
- I-PUBC-04: publisher A sets listing status to `published` (requires release)
- I-PUBC-05: publisher B cannot:
  - read A’s publisher listing detail endpoint (IDOR-safe `NOT_FOUND`)
  - update A’s listing
  - publish a release for A’s listing
- I-PUBC-06: non-publisher user cannot access publisher write endpoints (`UNAUTHORIZED`)

### 4.3 Release uniqueness and immutability (MUST)
**Tests:**
- I-REL-01: publishing the same `version` twice for same listing → `CONFLICT`
- I-REL-02: revoke release changes status without deletion
- I-REL-03: revoked release is not installable (install intent creation should fail or be blocked)
- I-REL-04: release record is immutable except allowed status transitions (if enforced)

### 4.4 Buyer install intents + token issuance (MUST)
**Setup:** User C is buyer.

**Tests:**
- I-INST-01: buyer creates install intent for `published` listing + `published` release
- I-INST-02: buyer lists own install intents (pagination works)
- I-INST-03: buyer issues install token (TTL respected, short-lived default)
- I-INST-04: buyer cannot issue token for someone else’s install intent (`NOT_FOUND`)
- I-INST-05: buyer cannot create install intent for:
  - non-existent listing/release
  - release that does not belong to listing
  - revoked release
- I-INST-06: idempotency on:
  - create intent (`Idempotency-Key` required)
  - issue token (`Idempotency-Key` required)
  - same key + different payload returns `CONFLICT`

### 4.5 Internal redemption endpoint hardening (MUST)
**Goal:** prove `/v1/internal/install/redeem` cannot be used as a browser vector and handles tokens safely.

**Tests:**
- I-INT-01: unauthenticated browser-style request rejected (CORS/origin checks if present; but do not rely solely on CORS)
- I-INT-02: missing/invalid server auth rejected (`UNAUTHENTICATED`)
- I-INT-03: valid server auth:
  - resolves install token to install intent + listing/release refs
  - marks token as redeemed if single-use (or otherwise records redemption idempotently)
- I-INT-04: redeeming an expired token returns `NOT_FOUND` (recommended) or consistent failure code
- I-INT-05: redeeming a revoked token returns `NOT_FOUND` (recommended) or consistent failure code
- I-INT-06: redeeming a redeemed single-use token again returns `NOT_FOUND` (recommended) / no repeated side effects
- I-INT-07: internal redemption response is secret-free:
  - no raw token
  - no internal auth headers
  - no private moderation fields
- I-INT-08: internal endpoint rate limit / quota behavior triggers on abuse pattern (if implemented)

---

## 5) End-to-end (E2E) test plan (MUST)

E2E tests validate real flows across UI + API + auth.

### 5.1 E2E-01: Signed-out browse/search
Steps:
1. Visit marketplace homepage.
2. Search for a known published listing.
3. Open listing detail and verify it renders safely.

Assertions:
- Only published listings visible.
- Description renders without executing scripts.
- Links follow outbound policy.

### 5.2 E2E-02: Publisher creates listing → publishes release → publishes listing
Steps:
1. Sign in as publisher A.
2. Create listing (draft).
3. Publish a release (references present).
4. Set listing status to `published`.
5. Sign out and verify listing appears publicly.

Assertions:
- Public listing contains expected fields.
- Release history visible.
- No private publisher-console fields leaked.

### 5.3 E2E-03: Buyer install intent + token issuance
Steps:
1. Sign in as buyer C.
2. Open a published listing.
3. Click “Install” and choose target system (at least one).
4. Create install intent and issue token.

Assertions:
- Token is issued and has an expiry timestamp.
- Buyer can see their install intent list.
- No token value appears in URL query params if avoidable (if UI policy is to avoid it).

### 5.4 E2E-04: Server-to-server redemption (integration seam)
Steps:
1. Using a test harness that can perform server-authenticated calls, call `/v1/internal/install/redeem` with the install token.
2. Validate response provides release references and intent details.
3. Redeem again (if single-use enabled).

Assertions:
- First redeem succeeds.
- Second redeem fails deterministically (single-use) without leaking token existence (recommended `NOT_FOUND`).
- Response contains only references + bounded metadata.

---

## 6) Security-focused test suite (MUST)

### 6.1 Tenant isolation / IDOR tests (MUST)
Create a dedicated suite that attempts cross-tenant reads and writes by id.

**Required cases:**
- S-IDOR-01: publisher B tries to `GET /v1/publisher/listings/:listingId` for A’s listing → `NOT_FOUND`
- S-IDOR-02: publisher B tries to `PATCH` A’s listing → `NOT_FOUND`
- S-IDOR-03: buyer D tries to `GET /v1/install/intents/:installIntentId` for buyer C → `NOT_FOUND`
- S-IDOR-04: buyer D tries to mint a token for buyer C’s intent → `NOT_FOUND`
- S-IDOR-05: public `GET /v1/public/listings/:listingId` for draft listing returns `NOT_FOUND`

### 6.2 XSS tests (MUST)
- S-XSS-01: stored XSS payload in listing description does not execute on listing detail page
- S-XSS-02: stored XSS payload in release notes does not execute
- S-XSS-03: markdown links do not allow `javascript:` or unsafe schemes

### 6.3 Confused deputy prevention tests (MUST)
- S-CD-01: internal redemption endpoint rejects browser-originated calls (no valid server auth)
- S-CD-02: redeem endpoint does not perform side effects (only resolves intent; no upstream calls)
- S-CD-03: install intent creation does not grant install completion state

### 6.4 Secrets leakage tests (MUST)
- S-SEC-01: responses never contain:
  - install token values except at issuance response (and even then, only once)
  - internal service auth material
- S-SEC-02: logs do not contain token values (requires a log capture harness in tests or deterministic redaction unit tests)
- S-SEC-03: normalized errors do not include sensitive payloads

### 6.5 Abuse / rate limits (SHOULD; MUST if publicly deployed)
- S-RL-01: public search rate limit triggers for high-frequency requests
- S-RL-02: publisher write rate limits trigger for rapid listing creations
- S-RL-03: install token issuance rate limit triggers for rapid token minting

---

## 7) Resilience and failure-mode tests (required)

### 7.1 Idempotency under retries
- R-IDEMP-01: retry listing creation with same idempotency key returns same listing
- R-IDEMP-02: retry release publish with same key returns same release
- R-IDEMP-03: retry install intent create with same key returns same intent
- R-IDEMP-04: same key + different payload returns `CONFLICT`

### 7.2 Token boundary edge cases
- R-TOK-01: token expiry boundary (just before expiry succeeds; after expiry fails)
- R-TOK-02: issuing a new token revokes old token (if policy enabled)
- R-TOK-03: redemption is idempotent under transient failures (e.g., if redemption marks token redeemed first, subsequent retry should not re-succeed)

### 7.3 Pagination stability
- R-PAG-01: listing search pagination returns consistent `nextCursor`
- R-PAG-02: release history pagination stable under concurrent new releases

---

## 8) Performance and load testing (recommended)

### 8.1 Public search endpoint
- Ensure `q` input is bounded and does not trigger pathological CPU usage.
- Under modest load, endpoints remain responsive.

### 8.2 Token redemption
- Redemption endpoint must be fast and bounded (hash lookup + intent fetch + response).
- Ensure rate limiting/quotas protect it from brute force.

---

## 9) Release gates (must-pass checklist)
Before shipping v1 to production, you MUST have:
- [ ] All **Unit (MUST)** tests passing (§3)
- [ ] All **Integration (MUST)** tests passing (§4)
- [ ] All **E2E (MUST)** tests passing (§5)
- [ ] All **Security (MUST)** tests passing (§6)
- [ ] A manual verification of:
  - CSP header present (if UI exists)
  - public endpoints not leaking drafts/unlisted content
  - internal endpoints not callable without server auth
- [ ] A basic operational runbook for abuse spikes:
  - how to tighten rate limits
  - how to suspend listings
  - how to revoke tokens/intents if needed

---

## 10) Acceptance criteria (system-level definition of done)

FleetPrompt v1 is “done” when:

### 10.1 Marketplace works (public)
- A signed-out user can browse/search published listings.
- Listing detail pages render safely (no XSS).
- Only `published` listings are visible publicly.

### 10.2 Publisher console works (tenant-safe)
- A publisher can:
  - create a listing (draft)
  - publish a release (with correct references for asset kind)
  - publish/unlist the listing
  - revoke a release
- Cross-publisher access is blocked:
  - publisher B cannot read/mutate A’s listing/release via console endpoints.

### 10.3 Install handoff works and is safe
- A buyer can:
  - create an install intent for a published release
  - issue an install token
- Tokens are:
  - short-lived
  - revocable
  - single-use by default (recommended)
- Internal redemption is:
  - server-to-server only
  - idempotent
  - secret-free in responses

### 10.4 Idempotency is proven
- For each idempotent endpoint:
  - same key + same payload returns same result
  - same key + different payload returns `CONFLICT`

### 10.5 “References, not copies” is preserved
- FleetPrompt does not persist upstream:
  - execution logs
  - telemetry events
  - transcripts
- Any UI “details” beyond FleetPrompt data is provided by deep links or on-demand fetches from owning systems (out of scope for v1, but boundary must remain true).

### 10.6 Abuse controls exist (minimum viable)
- Public search endpoints are rate-limited.
- Publisher write endpoints are rate-limited.
- Token issuance and redemption endpoints are rate-limited or otherwise quota-protected.

---

## 11) Appendix: Minimal test matrix (quick reference)

### Unit (MUST)
- Validators (lengths, enums, URL policy)
- Markdown sanitization determinism + XSS neutralization
- Idempotency ledger logic
- Token lifecycle (expiry, single-use, revocation)

### Integration (MUST)
- Public listing visibility rules
- Publisher CRUD + release publish/revoke + version uniqueness
- Buyer install intents + token issuance + IDOR safety
- Internal redemption server-to-server auth + token state transitions

### E2E (MUST)
- Browse/search as signed-out
- Publisher publish flow end-to-end
- Buyer install intent + token issuance
- Server-to-server redemption seam test

### Security (MUST)
- IDOR suite
- XSS suite
- Confused deputy protections for internal endpoints
- Secrets leakage checks