# fleetprompt.com — API Contracts (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-02-01

This document defines the **FleetPrompt v1** API surface and wire contracts:
- normalized error envelope (required)
- cursor pagination (required)
- idempotency for retryable writes (required)
- marketplace read endpoints (public)
- publisher console endpoints (authenticated)
- **install handoff** endpoints (authenticated; server-side redemption by target systems)

FleetPrompt is **Layer 5** (marketplace/distribution). It MUST remain **reference-first** and MUST NOT execute agents/workflows.

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Principles

### 1.1 Reference-first boundary (hard rule)
FleetPrompt MUST store and return:
- opaque identifiers to upstream assets (`whsAgentId`, `agentromaticWorkflowId`, etc.)
- bounded, secret-free summaries/snippets for UX

FleetPrompt MUST NOT:
- mirror upstream execution logs or telemetry (WHS metrics, Agentromatic execution logs)
- claim install success without authoritative confirmation from the owning system (optional, deferred)

### 1.2 Public vs authenticated surfaces
- Public endpoints are read-only and MUST be hardened against scraping/abuse.
- Publisher endpoints MUST enforce tenant isolation: publisher A cannot mutate publisher B’s listings/releases.
- Install intent endpoints are authenticated and user-scoped; redemption is server-to-server.

### 1.3 Stability rules (v1)
- IDs are **opaque strings**.
- Additive changes are allowed; breaking changes require `/v2`.
- Enums are closed in v1; adding new values is additive but MUST be documented.

### 1.4 Error consistency (REQUIRED)
All non-2xx responses MUST use the normalized error envelope in §3.

### 1.5 Pagination (REQUIRED)
All list/search endpoints MUST use cursor pagination (`nextCursor`) as in §2.4.

### 1.6 Idempotency (REQUIRED for retryable writes)
All endpoints that can be retried without user confirmation MUST accept an `Idempotency-Key` header and dedupe on it (see §2.5).

### 1.7 Time representation
All timestamps use **epoch milliseconds** (`createdAtMs`, `updatedAtMs`, etc.).

---

## 2) Common types

### 2.1 IDs (opaque strings)
FleetPrompt uses string IDs:
- `listingId`
- `releaseId`
- `installIntentId`
- `publisherId`
- `userId` (internal FleetPrompt user id, if exposed; otherwise external identity remains opaque)

Upstream references (opaque strings):
- `whsAgentId`, `whsDeploymentId?`
- `agentromaticWorkflowId`
- `agentelicTelespaceId?` (only for install target context)
- `delegaticOrgId?` (optional target context)

### 2.2 Enums

#### 2.2.1 ListingStatus
- `draft`
- `published`
- `unlisted`
- `suspended`

#### 2.2.2 AssetKind
- `whs_agent`
- `agentromatic_workflow`
- `spec_asset` (optional in v1; allowed to exist but may be unimplemented)

#### 2.2.3 ReleaseStatus
- `published`
- `revoked`

#### 2.2.4 InstallTargetSystem
- `whs`
- `agentromatic`
- `agentelic`

#### 2.2.5 InstallIntentStatus
- `created`
- `token_issued`
- `redeemed`
- `expired`
- `canceled`

#### 2.2.6 VerificationStatus (optional v1)
- `unverified`
- `verified`
- `failed`

### 2.3 Roles (FleetPrompt internal)
FleetPrompt is marketplace-facing; minimal roles:
- `user` (default)
- `publisher`
- `admin`

Role representation is an implementation detail, but endpoints MUST enforce equivalent authz semantics.

### 2.4 Pagination
List endpoints return:

- `items: T[]`
- `nextCursor: string | null`

Request parameters:
- `limit?: number` (default 50, max 200)
- `cursor?: string` (opaque cursor from previous response)

### 2.5 Idempotency
Retryable write endpoints accept:

- Header: `Idempotency-Key: <opaque string>`

Rules:
- MUST be scoped to the caller (publisher/user) and endpoint.
- MUST NOT include secrets or user-generated content.
- Server MUST store a dedupe record keyed by `(callerScope, endpoint, idempotencyKey)` returning:
  - the original successful response payload for duplicate requests, OR
  - a deterministic error if the same key is reused with a materially different payload (`CONFLICT`).

Recommended TTL: 24 hours (implementation detail).

### 2.6 Content and size limits (recommended baseline)
- `name`: 1..80 chars
- `summary`: 0..240 chars
- `description`: 0..20_000 chars (markdown)
- `tags[]`: max 20, each 1..32 chars
- `categories[]`: max 10, each 1..32 chars
- `images[]`: max 10
- `docsUrl`, `repoUrl`: max 2048 chars
- Request JSON body max: 256KB (public endpoints should be smaller)

---

## 3) Normalized errors (REQUIRED)

### 3.1 Error envelope
All errors MUST return:

```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "error": {
    "code": "STRING_CODE",
    "message": "Human-friendly, safe message",
    "requestId": "opaque-request-id",
    "details": {
      "hint": "optional safe hint",
      "fields": [
        { "fieldName": "path.to.field", "message": "what is wrong" }
      ]
    }
  }
}
```

Notes:
- `details` is optional.
- `fields` is optional.
- `requestId` MUST be present (generated server-side).

### 3.2 Error codes (v1)
- `UNAUTHENTICATED`
- `UNAUTHORIZED`
- `NOT_FOUND`
- `VALIDATION_FAILED`
- `CONFLICT`
- `RATE_LIMITED`
- `TOO_LARGE`
- `UNSUPPORTED`
- `INTERNAL`

### 3.3 Not found vs unauthorized strategy (IDOR-safe)
For private resources (publisher console, install intents/tokens), FleetPrompt SHOULD return `NOT_FOUND` when:
- the resource exists but is not visible to the caller

This reduces existence-oracle leaks. If you choose `UNAUTHORIZED` instead, it MUST be consistent across endpoints.

### 3.4 Validation errors
For `VALIDATION_FAILED`, include `details.fields[]` with field paths and messages.

---

## 4) Authentication & authorization

### 4.1 Authentication
All non-public endpoints require authentication. The auth mechanism is out of scope; it MUST provide:
- a stable subject identifier (external id)
- a server-resolved internal user/publisher scope

### 4.2 Tenant isolation (hard rule)
All mutations MUST be scoped by:
- `publisherId` for listings/releases
- `buyerUserId` for install intents

No endpoint may accept a `publisherId` from the client to select a write scope; scope is derived from the authenticated identity.

### 4.3 Authorization rules (v1 baseline)
- Public read: anyone can list/search/get published listings.
- Publisher endpoints: only publisher (or admin) can create/update their listings/releases.
- Admin endpoints: admin-only; keep minimal in v1.

Install intents:
- Only the buyer can create and view their install intents.
- Redemption MUST be server-to-server by a target system using a service auth mode (see §8.3).

---

## 5) Resource shapes (v1)

### 5.1 Listing (public shape)
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "listingId": "string",
  "assetKind": "whs_agent | agentromatic_workflow | spec_asset",
  "status": "draft | published | unlisted | suspended",
  "name": "string",
  "summary": "string",
  "tags": ["string"],
  "categories": ["string"],
  "publisher": {
    "publisherId": "string",
    "displayName": "string",
    "verified": {
      "status": "unverified | verified | failed",
      "checkedAtMs": 0,
      "reason": "string"
    }
  },
  "images": [
    { "url": "string", "alt": "string" }
  ],
  "links": {
    "docsUrl": "string",
    "repoUrl": "string"
  },
  "stats": {
    "installAttempts30d": 0,
    "downloads30d": 0
  },
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

Notes:
- `stats` MAY be omitted or delayed in v1.
- `verified` is informational only; never an authorization grant.

### 5.2 ListingDetail (public shape)
Adds long-form content + release pointers:

```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "listing": { /* Listing */ },
  "description": {
    "format": "markdown",
    "markdown": "string"
  },
  "latestRelease": { "releaseId": "string", "version": "string", "publishedAtMs": 0 },
  "releases": {
    "items": [
      { "releaseId": "string", "version": "string", "status": "published|revoked", "publishedAtMs": 0 }
    ],
    "nextCursor": "string|null"
  }
}
```

### 5.3 PublisherListing (publisher console shape)
Publisher view MAY include additional private fields not returned publicly:

```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "listingId": "string",
  "assetKind": "whs_agent | agentromatic_workflow | spec_asset",
  "status": "draft | published | unlisted | suspended",
  "name": "string",
  "summary": "string",
  "description": { "format": "markdown", "markdown": "string" },
  "tags": ["string"],
  "categories": ["string"],
  "images": [{ "url": "string", "alt": "string" }],
  "links": { "docsUrl": "string", "repoUrl": "string" },
  "moderation": {
    "flagged": false,
    "reason": "string"
  },
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

`moderation` MUST NOT be returned on public endpoints.

### 5.4 Release (public shape)
Releases are immutable and reference-first.

```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "releaseId": "string",
  "listingId": "string",
  "version": "string",
  "status": "published | revoked",
  "compat": {
    "minWHSVersion": "string",
    "minAgentromaticVersion": "string",
    "minAgentelicVersion": "string"
  },
  "refs": {
    "whsAgentId": "string",
    "whsDeploymentId": "string",
    "agentromaticWorkflowId": "string",
    "specAssetId": "string"
  },
  "artifacts": [
    {
      "kind": "source_bundle | build_artifact | manifest",
      "sha256": "string",
      "sizeBytes": 0,
      "download": {
        "mode": "none | fleetprompt_signed_url | specprompt_fulfillment",
        "hint": "string"
      }
    }
  ],
  "notes": {
    "format": "markdown",
    "markdown": "string"
  },
  "publishedAtMs": 0
}
```

Rules:
- `refs` fields are mutually constrained by `assetKind` (see §6.2.6).
- `artifacts.download.mode` indicates how to get artifacts; FleetPrompt SHOULD prefer SpecPrompt fulfillment for paid content.

### 5.5 InstallIntent (user-private)
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "installIntentId": "string",
  "buyerUserId": "string",
  "listingId": "string",
  "releaseId": "string",
  "targetSystem": "whs | agentromatic | agentelic",
  "targetContext": {
    "telespaceId": "string",
    "roomId": "string",
    "orgId": "string"
  },
  "status": "created | token_issued | redeemed | expired | canceled",
  "expiresAtMs": 0,
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

Notes:
- `buyerUserId` MAY be omitted from responses to clients if derived from auth; included here for clarity.

### 5.6 InstallTokenResponse
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "installIntentId": "string",
  "installToken": "string",
  "expiresAtMs": 0,
  "redeem": {
    "mode": "server_to_server",
    "targetSystem": "whs | agentromatic | agentelic"
  }
}
```

---

## 6) Endpoints (HTTP form, v1)

### 6.1 Public marketplace

#### 6.1.1 Search listings (public)
`GET /v1/public/listings/search?q=...&tags=...&categories=...&assetKind=...&sort=...&cursor=...&limit=...`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "items": [ /* Listing[] (public) */ ],
  "nextCursor": "string|null"
}
```

Rules:
- Only `status=published` listings are returned.
- Rate limiting MUST apply.

#### 6.1.2 Get listing detail (public)
`GET /v1/public/listings/:listingId`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "listingDetail": { /* ListingDetail */ }
}
```

If the listing is not published, return `NOT_FOUND` (do not leak draft listings).

#### 6.1.3 List releases for listing (public)
`GET /v1/public/listings/:listingId/releases?cursor=...&limit=...`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "items": [ /* {releaseId, version, status, publishedAtMs}[] */ ],
  "nextCursor": "string|null"
}
```

Rules:
- If listing is not published, return `NOT_FOUND`.
- Revoked releases MAY be hidden from public by default; if shown, clearly mark status.

---

### 6.2 Publisher console (authenticated)

#### 6.2.1 List my listings
`GET /v1/publisher/listings?cursor=...&limit=...&status=...`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "items": [ /* PublisherListing[] */ ],
  "nextCursor": "string|null"
}
```

#### 6.2.2 Create listing (idempotent)
`POST /v1/publisher/listings`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "assetKind": "whs_agent | agentromatic_workflow | spec_asset",
  "name": "string",
  "summary": "string",
  "description": { "format": "markdown", "markdown": "string" },
  "tags": ["string"],
  "categories": ["string"],
  "images": [{ "url": "string", "alt": "string" }],
  "links": { "docsUrl": "string", "repoUrl": "string" }
}
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "listing": { /* PublisherListing */ }
}
```

Behavior:
- New listings default to `status="draft"`.

#### 6.2.3 Get my listing
`GET /v1/publisher/listings/:listingId`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "listing": { /* PublisherListing */ } }
```

IDOR-safe: if listing is not owned by caller, return `NOT_FOUND`.

#### 6.2.4 Update listing (idempotent recommended)
`PATCH /v1/publisher/listings/:listingId`

Headers:
- `Idempotency-Key: <string>` (SHOULD)

Request (patch semantics; all fields optional):
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "name": "string",
  "summary": "string",
  "description": { "format": "markdown", "markdown": "string" },
  "tags": ["string"],
  "categories": ["string"],
  "images": [{ "url": "string", "alt": "string" }],
  "links": { "docsUrl": "string", "repoUrl": "string" }
}
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true }
```

#### 6.2.5 Set listing status (publish/unlist)
`POST /v1/publisher/listings/:listingId/status`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "status": "draft | published | unlisted" }
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true }
```

Notes:
- `suspended` is admin-only (see §6.6).
- Publishing SHOULD require at least one `published` release, or the UI should clearly handle “no releases yet” listings.

#### 6.2.6 Publish release (idempotent)
`POST /v1/publisher/listings/:listingId/releases`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "version": "string",
  "refs": {
    "whsAgentId": "string",
    "whsDeploymentId": "string",
    "agentromaticWorkflowId": "string",
    "specAssetId": "string"
  },
  "compat": {
    "minWHSVersion": "string",
    "minAgentromaticVersion": "string",
    "minAgentelicVersion": "string"
  },
  "artifacts": [
    {
      "kind": "source_bundle | build_artifact | manifest",
      "sha256": "string",
      "sizeBytes": 0,
      "download": {
        "mode": "none | fleetprompt_signed_url | specprompt_fulfillment",
        "hint": "string"
      }
    }
  ],
  "notes": { "format": "markdown", "markdown": "string" }
}
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "release": { /* Release */ } }
```

Validation rules (MUST):
- `version` MUST be unique per `(listingId)`.
- `refs` MUST match listing `assetKind`:
  - `whs_agent` requires `refs.whsAgentId`
  - `agentromatic_workflow` requires `refs.agentromaticWorkflowId`
  - `spec_asset` requires `refs.specAssetId` (if supported)
- `whsDeploymentId` is optional and MUST be treated as a hint only.

#### 6.2.7 Revoke release (idempotent)
`POST /v1/publisher/releases/:releaseId/revoke`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "reason": "string" }
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true }
```

Rules:
- Revocation is a state transition, not deletion.
- Public endpoints SHOULD hide revoked releases by default.

---

### 6.3 Buyer install handoff (authenticated)

#### 6.3.1 Create install intent (idempotent)
`POST /v1/install/intents`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "listingId": "string",
  "releaseId": "string",
  "targetSystem": "whs | agentromatic | agentelic",
  "targetContext": {
    "telespaceId": "string",
    "roomId": "string",
    "orgId": "string"
  }
}
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "installIntent": { /* InstallIntent */ }
}
```

Rules:
- Validate that `releaseId` belongs to `listingId` and is `published` (and not revoked) for install.
- `targetContext` must be bounded and treated as opaque. FleetPrompt does not validate telespace/org existence in v1 (optional verification later).

#### 6.3.2 Issue install token (idempotent)
`POST /v1/install/intents/:installIntentId/token`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ttlMs": 3600000 }
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ /* InstallTokenResponse */ }
```

Rules:
- Only the intent owner can issue tokens.
- Default TTL should be short (10–60 min).
- Token should be single-use; issuing a new token MAY invalidate the old one.

#### 6.3.3 List my install intents
`GET /v1/install/intents?cursor=...&limit=...&status=...`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "items": [ /* InstallIntent[] */ ], "nextCursor": "string|null" }
```

#### 6.3.4 Get my install intent
`GET /v1/install/intents/:installIntentId`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "installIntent": { /* InstallIntent */ } }
```

IDOR-safe: return `NOT_FOUND` if not owned by caller.

---

### 6.4 Target-system redemption surface (server-to-server)

FleetPrompt MUST support redemption in a way that:
- prevents clients from redeeming tokens directly with privileged side effects
- allows WHS/Agentromatic/Agentelic servers to redeem with their own authorization checks

Two acceptable v1 designs:
- **R1 (recommended):** Target systems call FleetPrompt to resolve a token to an install intent.
- **R2:** FleetPrompt issues signed tokens that encode intent id and are verified locally by the target system (requires key distribution and rotation; higher complexity).

This spec defines **R1**.

#### 6.4.1 Redeem token (resolve to intent + references)
`POST /v1/internal/install/redeem`

Authentication:
- MUST be server-to-server.
- Auth mode (v1): HMAC over **raw request body bytes** + timestamp skew window (locked by `ADR-0003`).
- Required headers (MUST):
  - `X-WHS-Delegation-Source: <string>`
  - `X-WHS-Delegation-Timestamp: <epoch_ms_as_string>`
  - `X-WHS-Delegation-Signature: v1=<hex(hmac_sha256(raw_body_bytes, FLEETPROMPT_INTERNAL_REDEEM_SECRET))>`
- Verification rules (MUST):
  - Verify the signature over the **exact raw request body bytes** BEFORE parsing JSON.
  - Enforce a timestamp skew window of **±5 minutes**.
  - Reject missing/invalid headers or failed verification as `UNAUTHENTICATED`.
- Defense-in-depth (SHOULD):
  - Enforce an allowlist for `X-WHS-Delegation-Source` (e.g., `whs`, `agentromatic`, `agentelic`).

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "installToken": "string",
  "targetSystem": "whs | agentromatic | agentelic"
}
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "installIntent": { /* InstallIntent */ },
  "listing": {
    "listingId": "string",
    "assetKind": "whs_agent | agentromatic_workflow | spec_asset",
    "name": "string"
  },
  "release": {
    "releaseId": "string",
    "version": "string",
    "refs": { /* same as Release.refs */ },
    "compat": { /* same as Release.compat */ },
    "artifacts": [ /* same as Release.artifacts */ ]
  }
}
```

Rules:
- If token is expired/revoked/used: return `NOT_FOUND` or `CONFLICT` (consistent strategy).
- The response MUST be safe and secret-free.
- FleetPrompt MUST mark token as redeemed (single-use) or perform an idempotent redemption record.

#### 6.4.2 Optional: Redemption acknowledgment callback (deferred)
If FleetPrompt wants to record “install succeeded”, it MUST do so only via an authenticated callback from the target system:
- `POST /v1/internal/install/ack`
- includes installIntentId + outcome + target system correlation id
- fully audited, idempotent

This is optional and deferred; do not invent “success” states without it.

---

### 6.5 Health and metadata

#### 6.5.1 Health check (public)
`GET /healthz`

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true, "version": "1.0" }
```

---

### 6.6 Admin endpoints (optional v1, minimal)

#### 6.6.1 Suspend listing (admin)
`POST /v1/admin/listings/:listingId/suspend`

Headers:
- `Idempotency-Key: <string>` (REQUIRED)

Request:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "reason": "string" }
```

Response:
```ProjectWHS/fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true }
```

Rules:
- Suspension hides listing from public.
- Publisher can view suspension status in console with safe reason.

---

## 7) Install handoff semantics (v1)

### 7.1 FleetPrompt does not authorize installs
FleetPrompt’s job is to:
- produce a verifiable intent and token
- provide references and artifact pointers

The target system MUST:
- authenticate the user (or resolve identity via its own mechanism)
- enforce ownership/membership/role checks
- perform install/import in its own domain

### 7.2 Idempotency at redemption
Redemption MUST be idempotent:
- resolving the same token multiple times should not create multiple installs
- the target system SHOULD use its own idempotency key derived from:
  - `(installIntentId, targetSystem)` plus target context

### 7.3 No secrets in install flows
Install intents/tokens MUST NOT embed:
- API keys
- OAuth tokens
- runtime secrets
- user message content

---

## 8) Security requirements (API-level)

### 8.1 Public endpoint hardening
Public endpoints MUST implement:
- rate limits (`RATE_LIMITED`)
- response shaping (no private fields)
- pagination caps
- safe query handling (avoid regex DoS)

### 8.2 UGC safety
Where FleetPrompt accepts content for listing description/notes:
- sanitize markdown to a safe subset
- forbid raw HTML
- protect against XSS and link hijacking
- enforce size limits

### 8.3 Internal endpoints MUST be non-browser callable
All `/v1/internal/*` endpoints MUST:
- require server-to-server authentication
- reject CORS/browser-originated calls
- treat payloads as untrusted and validate strictly

---

## 9) Open questions (to resolve as ADRs)
1. What is the exact server-to-server auth scheme for `/v1/internal/install/redeem`?
2. Does FleetPrompt host artifacts in v1, or are all artifacts fulfilled via SpecPrompt / upstream?
3. Are revoked releases visible to publisher only, or also to public with status label?
4. Does publishing require an automated verification step (e.g., check that referenced `whsAgentId` exists)? (Recommended: optional verification status only, never an authorization bypass.)

---

## 10) Minimal v1 contract checklist (Definition of Done for API)
- [ ] All endpoints return normalized errors.
- [ ] All list/search endpoints paginate with `nextCursor`.
- [ ] Retryable writes require `Idempotency-Key` and dedupe correctly.
- [ ] Public endpoints expose only published content and are rate-limited.
- [ ] Publisher endpoints enforce tenant isolation (IDOR-safe).
- [ ] Install intents + token issuance work end-to-end.
- [ ] Internal redeem endpoint exists and is server-to-server only.
- [ ] No secrets appear in logs, stored records, or responses.
