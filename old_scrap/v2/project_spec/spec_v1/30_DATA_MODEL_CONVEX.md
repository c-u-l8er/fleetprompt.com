# fleetprompt.com — Data Model (Convex) & Access Control (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines the **FleetPrompt v1** data model (Convex) and the **required access control + invariants**.

FleetPrompt is **Layer 5** (marketplace/distribution). It MUST be **reference-first** and MUST NOT:
- execute agents/workflows,
- mirror upstream telemetry/logs/transcripts,
- store plaintext secrets.

---

## 0) Design goals

### 0.1 Goals (v1)
- Support a public marketplace (browse/search published listings + release history).
- Support publisher console (listing CRUD + release publishing + revocation).
- Support buyer install handoff:
  - create install intents (user-scoped),
  - mint revocable install tokens (short-lived, preferably single-use),
  - server-to-server redemption resolution (internal endpoint; auth scheme via ADR).
- Support idempotency and safe retries for all retryable writes.
- Support moderation controls (minimal v1) without leaking private flags publicly.
- Be explicit about access control and IDOR-safe behaviors.

### 0.2 Non-goals (v1)
- Payments/commerce ledger (SpecPrompt owns).
- Publisher payouts / marketplace financials.
- Full trust scoring / advanced verification (basic informational verification only).

---

## 1) Cross-cutting conventions (normative)

### 1.1 Identity model (recommended baseline)
FleetPrompt maintains a `users` table keyed by `externalId` (auth provider subject).
- All auth-required operations MUST resolve the caller to `users._id`.
- If missing, create user row on demand (server-side only).

Canonical fields:
- `users.externalId: string` (unique, indexed)
- optional profile: `email?`, `displayName?` (bounded; do not rely on email uniqueness)

### 1.2 Time
Use epoch milliseconds consistently:
- `createdAtMs`, `updatedAtMs`, `publishedAtMs`, `expiresAtMs`, etc.

### 1.3 IDs
Convex `_id` values are internal IDs. API IDs may either:
- expose Convex IDs as strings (simplest), or
- wrap them in prefixed IDs (`lst_...`) (more work)

Decision MUST be consistent across API + data model + UI. (If not decided, treat API IDs as Convex doc IDs serialized to string.)

### 1.4 Tenancy and “owner scope”
FleetPrompt v1 is primarily **user-scoped**:
- Publisher ownership is represented by `publisherUserId: Id<"users">` for listings/releases.
- Buyer ownership is represented by `buyerUserId: Id<"users">` for install intents.

No endpoint may accept a `publisherUserId` as an argument to select a write scope. Derive scope from caller identity.

### 1.5 Payload size limits (MUST enforce)
FleetPrompt is UGC-heavy; enforce strict limits server-side:
- listing `name`: <= 80 chars
- `summary`: <= 240 chars
- `descriptionMarkdown`: <= 20_000 chars (safe markdown only)
- `tags[]`: <= 20 items, each <= 32 chars
- `categories[]`: <= 10 items, each <= 32 chars
- release `notesMarkdown`: <= 10_000 chars
- install `targetContext` string fields: <= 200 chars each
- any “safe snippets” or “reason” fields: <= 1_000 chars
- request/response bodies should remain bounded by contract limits in `10_API_CONTRACTS.md`

### 1.6 Secrets rule (normative)
FleetPrompt MUST NOT store plaintext secrets, including:
- API keys, OAuth tokens, provider secrets,
- bearer tokens (except short-lived FleetPrompt-issued install tokens stored hashed or opaque id lookups).

If any token-like value is stored:
- store **only** a hash (preferred) or an opaque random token id that resolves server-side,
- enforce expiration,
- enforce single-use semantics if configured,
- never log token values.

### 1.7 “References, not copies” (normative)
FleetPrompt stores only references to upstream assets:
- `whsAgentId`, optional `whsDeploymentId` (hint only),
- `agentromaticWorkflowId`,
- optional spec asset identifiers (for SpecPrompt fulfillment).

FleetPrompt MUST NOT store:
- WHS telemetry events,
- Agentromatic execution logs,
- Agentelic room transcripts/messages.

---

## 2) Tables (normative schema)

> Naming note: this spec uses “table” as Convex collection. Use consistent names in `schema.ts`.

### 2.1 `users`
Purpose: Map auth-provider identity to internal user id and store minimal profile.

Fields:
- `externalId: string` (unique, indexed)
- `email?: string` (optional; bounded; DO NOT rely on for auth)
- `displayName?: string` (optional; bounded)
- `roles?: { publisher?: boolean, admin?: boolean }` (optional; or separate table)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- by `externalId`

Invariants:
- At most one user row per `externalId`.

---

### 2.2 `publisherProfiles` (optional; recommended for clean separation)
Purpose: Publisher metadata that can be shown on public listings.

Fields:
- `publisherUserId: Id<"users">` (indexed; unique per user)
- `displayName: string` (bounded)
- `bioMarkdown?: string` (bounded, sanitized)
- `verification: { status: "unverified"|"verified"|"failed", checkedAtMs?: number, reason?: string }`
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- by `publisherUserId`

Invariants:
- One profile per publisher user (recommended).
- `verification` is informational only; never grants privileges.

If you don’t create this table:
- store publisher display name and verification fields on `users` (but keep public/private separation clear).

---

### 2.3 `listings`
Purpose: Marketplace listing metadata + public page content.

Fields:
- `publisherUserId: Id<"users">` (owner; indexed)
- `assetKind: "whs_agent" | "agentromatic_workflow" | "spec_asset"`
- `status: "draft" | "published" | "unlisted" | "suspended"`
- `name: string` (bounded)
- `summary: string` (bounded)
- `descriptionMarkdown: string` (bounded; sanitized before display)
- `tags: string[]` (bounded)
- `categories: string[]` (bounded)
- `images: Array<{ url: string, alt?: string }>` (bounded; URLs validated)
- `links: { docsUrl?: string, repoUrl?: string }` (bounded; URLs validated)
- `search: { normalizedName: string, normalizedTags: string[], normalizedCategories: string[] }` (derived; used for search)
- `moderation: { flagged: boolean, reason?: string }` (internal; MUST NOT be returned on public endpoints)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required/recommended):
- by `publisherUserId` (publisher console list)
- by `status` + `updatedAtMs` (admin/moderation views and public listing list)
- by `assetKind` + `status` + `updatedAtMs` (public filters)
- search support:
  - Convex doesn’t provide full-text search natively; you can:
    - implement “contains” search over normalizedName (limited), or
    - maintain a separate `listingSearchTokens` table, or
    - integrate a search service later.
  - For v1, keep it simple:
    - prefix/substring match on `normalizedName`,
    - tag/category filters.

Invariants:
- `publisherUserId` is immutable after create (ownership cannot be transferred in v1).
- If `status="published"`, listing MUST have at least one published release (enforce at publish time).
- Public reads MUST return only `status="published"`.

---

### 2.4 `releases`
Purpose: Immutable release records for a listing.

Releases should be **append-only**: once created, do not modify fields except status transitions like `revoked`.

Fields:
- `listingId: Id<"listings">` (indexed)
- `publisherUserId: Id<"users">` (denormalized owner for fast auth checks; indexed)
- `version: string` (bounded; semver recommended)
- `status: "published" | "revoked"`
- `compat: { minWHSVersion?: string, minAgentromaticVersion?: string, minAgentelicVersion?: string }` (optional, bounded)
- `refs: {`
  - `whsAgentId?: string`
  - `whsDeploymentId?: string` (optional hint only)
  - `agentromaticWorkflowId?: string`
  - `specAssetId?: string`
  `}` (bounded)
- `notesMarkdown?: string` (bounded, sanitized before display)
- `artifacts?: Array<{ kind: "source_bundle"|"build_artifact"|"manifest", sha256?: string, sizeBytes?: number, download?: { mode: "none"|"fleetprompt_signed_url"|"specprompt_fulfillment", hint?: string } }>` (bounded)
- `publishedAtMs: number`
- `createdAtMs: number` (can equal `publishedAtMs`)

Indexes (required):
- by `listingId` + `publishedAtMs` (release history list)
- by `listingId` + `version` (for uniqueness checks and lookups)
- by `publisherUserId` + `createdAtMs` (publisher console views; optional but helpful)

Invariants (MUST):
- Release belongs to listing: `releases.listingId` references existing `listings` doc.
- `publisherUserId` MUST match `listings.publisherUserId` at creation.
- Version uniqueness per listing:
  - No two releases may exist with the same `(listingId, version)`.
- `refs` must match listing `assetKind`:
  - If listing.assetKind = `whs_agent` ⇒ `refs.whsAgentId` REQUIRED.
  - If listing.assetKind = `agentromatic_workflow` ⇒ `refs.agentromaticWorkflowId` REQUIRED.
  - If listing.assetKind = `spec_asset` ⇒ `refs.specAssetId` REQUIRED (if supported).
- Revocation is a state transition:
  - Do not delete the release; set `status="revoked"` and record audit event.
- Public endpoints SHOULD hide revoked releases by default, but publisher can view them.

---

### 2.5 `installIntents`
Purpose: User-scoped record representing an intent to install a specific release into a target system.

Fields:
- `buyerUserId: Id<"users">` (owner; indexed)
- `listingId: Id<"listings">`
- `releaseId: Id<"releases">`
- `targetSystem: "whs" | "agentromatic" | "agentelic"`
- `targetContext?: { telespaceId?: string, roomId?: string, orgId?: string }` (bounded; opaque strings)
- `status: "created" | "token_issued" | "redeemed" | "expired" | "canceled"`
- `expiresAtMs?: number` (optional; intent itself may expire)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- by `buyerUserId` + `createdAtMs` (list “my install intents”)
- by `releaseId` (optional; metrics, debugging)

Invariants:
- `buyerUserId` is immutable after create.
- `releaseId` MUST belong to `listingId`.
- The release MUST be installable when the intent is created:
  - `releases.status="published"` (and not revoked),
  - if listing is not published, install intent MAY still be allowed for preview/testing but MUST be explicit (v1 recommended: disallow unless listing published).
- `targetContext` is opaque and MUST NOT be treated as authorization.

---

### 2.6 `installTokens`
Purpose: Revocable, short-lived tokens issued for an install intent and redeemed server-to-server.

Security: Prefer storing **hashes** of tokens. If you store the raw token, you MUST treat it like a secret and never log it.

Fields:
- `installIntentId: Id<"installIntents">` (indexed)
- `buyerUserId: Id<"users">` (denormalized owner; indexed)
- `targetSystem: "whs" | "agentromatic" | "agentelic"` (indexed)
- `tokenHash: string` (recommended; store hex/urlsafe hash)
- `status: "issued" | "redeemed" | "expired" | "revoked"`
- `singleUse: boolean` (recommended true)
- `issuedAtMs: number`
- `expiresAtMs: number`
- `redeemedAtMs?: number`
- `redeemedBySystem?: "whs"|"agentromatic"|"agentelic"`
- `redeemCorrelationId?: string` (optional; bounded)
- `createdAtMs: number`

Indexes (required):
- by `installIntentId` + `issuedAtMs` (get latest token for intent)
- by `buyerUserId` + `createdAtMs` (buyer “my tokens” view, optional)
- by `tokenHash` (lookup by presented token during redemption)

Invariants:
- Token must belong to intent and buyer:
  - `installTokens.buyerUserId == installIntents.buyerUserId`
  - `installTokens.installIntentId == installIntents._id`
- `expiresAtMs` must be in the future when issuing.
- Single-use enforcement:
  - if `singleUse=true`, first successful redemption transitions to `redeemed`; subsequent lookups MUST fail (recommended: return NOT_FOUND).
- Issuing a new token MAY revoke previous issued tokens for the same intent (recommended v1 behavior to reduce token sprawl), but must be deterministic and audited.

---

### 2.7 `idempotencyKeys` (recommended; supports robust retry semantics)
Purpose: Deduplicate retryable writes (publisher listing create, release publish, install intent create, token issue).

Fields:
- `scope: { type: "user"|"publisher", userId: Id<"users"> }`
- `endpoint: string` (bounded; e.g., `"POST /v1/publisher/listings"`)
- `idempotencyKey: string` (bounded)
- `requestHash: string` (hash of normalized request body)
- `response: { ok: boolean, bodyJson: any }` (bounded; store minimal or a reference)
- `createdAtMs: number`
- `expiresAtMs: number` (TTL; e.g., 24h)

Indexes (required):
- by `(scope.userId, endpoint, idempotencyKey)`

Invariants:
- If an existing record matches the same tuple:
  - if `requestHash` differs ⇒ `CONFLICT`
  - else return stored `response`

---

### 2.8 `auditLog` (recommended; append-only)
Purpose: Append-only audit trail for security, debugging, and support.

Fields:
- `type: string` (stable enum-like string; e.g. `listing.created`)
- `actor: { type: "user"|"system", userId?: Id<"users"> }`
- `publisherUserId?: Id<"users">` (if applicable)
- `listingId?: Id<"listings">`
- `releaseId?: Id<"releases">`
- `installIntentId?: Id<"installIntents">`
- `createdAtMs: number`
- `summary: string` (bounded)
- `details?: any` (bounded, secret-free)

Indexes (recommended):
- by `publisherUserId` + `createdAtMs`
- by `listingId` + `createdAtMs`
- by `installIntentId` + `createdAtMs`
- by `type` + `createdAtMs` (admin debugging)

Invariants:
- Append-only: no updates/deletes (except retention jobs if implemented).

---

### 2.9 `rateLimitBuckets` (optional; implementation detail)
Purpose: Rate limiting counters (public search, publishing, install intent creation).

Fields:
- `bucketKey: string` (e.g., `ip:<hash>:route:/v1/public/listings/search:window:2026-01-31T00:00Z`)
- `count: number`
- `windowStartMs: number`
- `windowEndMs: number`
- `createdAtMs: number`

Indexes:
- by `bucketKey`

Invariants:
- Counters must be bounded and reset by window semantics.

---

## 3) Access control requirements (normative)

### 3.1 Global rule (must)
Every query/mutation/action MUST:
1. Resolve caller identity to `users._id`.
2. Enforce visibility/ownership for the requested resource.
3. Return IDOR-safe errors:
   - recommended: for non-visible resources, behave as `NOT_FOUND`.

### 3.2 Public reads (marketplace)
Public reads MUST:
- return only `listings.status="published"`.
- not return:
  - `moderation` fields,
  - any private publisher metadata,
  - buyer install intents/tokens.
- be rate-limited and paginated.

### 3.3 Publisher console (writes and private reads)
For publisher operations:
- Caller must have publisher capability (role flag or policy).
- Ownership is enforced by `publisherUserId`:
  - can only modify listings where `listings.publisherUserId == callerUserId`.
  - can only publish/revoke releases for owned listings.
- Draft/unlisted listings are visible only to owner (and admin).

### 3.4 Buyer install intents and tokens
Install intent rules:
- Only the buyer can create/list/get their install intents.
- Only the buyer can issue tokens for their install intents.

Install token redemption rules:
- Redemption is server-to-server only and MUST NOT be callable by browsers.
- On redemption, FleetPrompt must:
  - resolve token (by hash),
  - confirm token is valid (not expired/revoked/redeemed),
  - return install intent + release refs in a secret-free response,
  - transition token state idempotently (single-use recommended),
  - write audit event.

### 3.5 Admin-only operations
Admin operations (suspension, moderation actions) MUST:
- be explicitly gated by admin role,
- be audited,
- avoid leaking private moderation notes publicly.

---

## 4) Deletion and retention semantics (normative)

### 4.1 Soft delete (recommended)
For core entities, prefer soft delete/state transitions:
- listings: `status="suspended"` or `status="unlisted"` rather than delete.
- releases: `status="revoked"` rather than delete.

Rationale:
- auditability,
- avoids dangling references in external systems.

### 4.2 Token retention
- Install tokens should expire quickly (minutes-hours).
- Expired/redeemed tokens may be retained short-term for audit (e.g., 30 days) then purged.

### 4.3 Audit log retention
- Retention must be defined before production.
- Recommended baseline: retain audit logs at least 90 days.

---

## 5) Indexing guidance (Convex-specific)

### 5.1 Public listing browsing
Required query patterns:
- list published listings sorted by `updatedAtMs desc`
  - index: `status, updatedAtMs`
- filter by assetKind
  - index: `assetKind, status, updatedAtMs`

### 5.2 Release history
- list releases for listing by `publishedAtMs desc`
  - index: `listingId, publishedAtMs`
- lookup by version for uniqueness checks
  - index: `listingId, version`

### 5.3 Publisher console
- list my listings
  - index: `publisherUserId, updatedAtMs`
- list releases for my listings
  - index: `publisherUserId, createdAtMs` (optional; otherwise join via listing)

### 5.4 Idempotency
- primary lookup is by `(scope.userId, endpoint, idempotencyKey)`.

### 5.5 Install token lookup
- lookup by `tokenHash` (required for redemption).
- list latest token for install intent:
  - `installIntentId, issuedAtMs` (take latest)

---

## 6) Validation requirements (must)

### 6.1 Schema validation
All writes MUST validate:
- types and enums,
- string lengths,
- array lengths,
- URLs (allowlist schemes: `https:` only recommended),
- markdown safe subset (no raw HTML),
- artifact `sha256` format if provided (hex string, bounded length).

### 6.2 Cross-table invariants
Must enforce:
- listing ownership for all publisher writes.
- release belongs to listing and matches owner at creation.
- release uniqueness per `(listingId, version)`.
- install intent refers to existing listing + release, and release belongs to listing.
- install token belongs to install intent and buyer.
- idempotency key reuse with different payload is `CONFLICT`.

### 6.3 Status transition rules (minimum)
- listing:
  - `draft` → `published` (requires at least one published release)
  - `published` → `unlisted` or `draft` (optional)
  - `*` → `suspended` (admin-only)
- release:
  - `published` → `revoked`
  - `revoked` is terminal (do not un-revoke; publish a new version)
- install token:
  - `issued` → `redeemed` (single-use)
  - `issued` → `expired` (time-based)
  - `issued` → `revoked` (new token issuance or explicit revoke)

---

## 7) Minimal v1 schema checklist (Definition of Done for data model)
- [ ] `users` with unique `externalId`
- [ ] `listings` with owner field and public/private split
- [ ] `releases` with per-listing version uniqueness enforcement
- [ ] `installIntents` with buyer scoping and bounded target context
- [ ] `installTokens` with hash lookup, expiry, and single-use semantics
- [ ] idempotency mechanism exists (`idempotencyKeys` table or equivalent)
- [ ] audit logging exists (recommended) and is append-only
- [ ] indexes exist for public browse, publisher console, release history, token redemption
- [ ] no plaintext secrets stored anywhere

---

## 8) Open decisions (should become ADRs)
1. Token storage strategy:
   - store only token hashes (recommended), plus secure hashing algorithm details.
2. Internal server-to-server auth scheme for redemption endpoints (HMAC/mTLS/etc.).
3. Search strategy:
   - keep minimal substring/tags in v1 vs integrate search service.
4. Artifact hosting:
   - does FleetPrompt host artifacts (R2/S3) or delegate to SpecPrompt fulfillment only?
5. Whether publisher profiles are a separate table vs on `users`.

---