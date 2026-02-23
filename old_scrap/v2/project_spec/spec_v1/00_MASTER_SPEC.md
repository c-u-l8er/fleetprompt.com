# fleetprompt.com — MASTER ENGINEERING SPEC (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

FleetPrompt is **Layer 5 (Marketplace / Distribution)** in the WHS 6-layer ecosystem.

- **Layer 1 — WebHost.Systems (WHS):** agent hosting, deploy/invoke, telemetry, limits/billing
- **Layer 2 — Agentromatic:** workflow definitions, executions, logs
- **Layer 3 — Agentelic:** telespaces (rooms/messages/membership), installs/automations (references)
- **Layer 4 — Delegatic:** orgs, policy inheritance, governance (references, deny-by-default)
- **Layer 5 — FleetPrompt (this):** discovery/listing/distribution + install handoff
- **Layer 6 — SpecPrompt:** commerce (checkout, licensing, entitlements, fulfillment)

This document is the canonical “what we are building” for FleetPrompt v1: scope, invariants, flows, acceptance criteria.

---

## 0) Executive summary

### 0.1 What you are building (v1)
FleetPrompt v1 is a **public-facing marketplace + publisher console** that:
1. Hosts a **catalog of listings** for ecosystem assets (agents, workflows, templates/spec assets).
2. Stores **release metadata** and (optionally) **artifact pointers** for those assets.
3. Provides an **install handoff mechanism** that lets a user take an asset from FleetPrompt into the owning system:
   - WHS (agents)
   - Agentromatic (workflows)
   - Agentelic (installed agents/workflows inside telespaces)
   - Delegatic (org-governed visibility; optional in v1)

FleetPrompt is **reference-first**:
- It stores references to upstream IDs (`whsAgentId`, `agentromaticWorkflowId`, etc.) plus bounded, secret-free summaries for UX/search.

### 0.2 What you are NOT building (v1)
FleetPrompt v1 MUST NOT:
- execute agents (WHS does that)
- execute workflows (Agentromatic does that)
- ingest or mirror upstream telemetry/logs/transcripts (only references + bounded summaries)
- bypass authorization in other products (no “marketplace purchase == runtime permission”)
- implement commerce/payout rails (handled by SpecPrompt, and optionally later publisher payouts)

---

## 1) Scope, goals, non-goals

### 1.1 Goals (v1 MUST)
FleetPrompt v1 MUST provide:

**Marketplace (read side)**
- Public browse/search listings (signed-out read-only).
- Listing detail pages with safe rendering, version/release history, compatibility metadata.
- Publisher identity + informational verification badges (optional in v1).

**Publisher console (write side)**
- Create/update listings (authenticated).
- Publish releases for a listing (authenticated).
- Manage listing status (`draft|published|unlisted|suspended`).
- See basic aggregate metrics (views/download attempts) without storing sensitive runtime data.

**Install handoff**
- An “Install” action that initiates a handoff to the owning product using one of:
  1) deep link to the owning system UI, OR
  2) generate a **redeemable install intent token** (recommended) that the owning system redeems server-side.

**Tenancy and security**
- Strict tenant isolation for write operations (publisher A cannot mutate publisher B’s assets).
- IDOR-safe reads for private resources (publisher console, buyer install intents).
- Strong UGC safety: input validation, sanitization, and abuse controls.

### 1.2 Non-goals (v1 MUST NOT)
FleetPrompt v1 MUST NOT:
- become the source of truth for upstream assets’ execution state or costs
- store secrets, API keys, OAuth tokens, or runtime credentials
- auto-install into other systems without explicit user action and server-side validation
- act as an authorization oracle for other systems
- provide enterprise org billing/admin features (defer to SpecPrompt + Delegatic later)

### 1.3 Assumptions
- A shared identity provider exists across portfolio products (e.g., a stable external user id).
- Upstream systems remain authoritative for:
  - access control, membership, roles, entitlements enforcement within their domain
- FleetPrompt is public-facing and will be exposed to untrusted content; abuse controls are mandatory.

---

## 2) Key decisions (ADR-style summaries)
(Write ADRs under `spec_v1/adr/` and keep them small and single-decision.)

- **References, not copies:** FleetPrompt stores upstream IDs + bounded summaries only.
- **Install is a handoff:** FleetPrompt initiates intent; the target system validates and executes install.
- **Entitlements vs authorization:** commerce rights never imply runtime authorization; systems must re-check membership/ownership.
- **UGC safety is mandatory:** safe rendering, size limits, and rate limits are required from day 1.
- **Idempotency by design:** all retryable writes and event processing MUST be idempotent.

---

## 3) Glossary (canonical terms)

- **Listing:** A marketplace page describing an asset (metadata + links + release history).
- **Release:** A versioned publication for a listing (e.g., semver) with optional artifact pointers and compatibility metadata.
- **Asset kind:** The category of thing being listed; v1 supports `whs_agent`, `agentromatic_workflow`, and optionally `spec_asset`.
- **Publisher:** The identity that owns listings/releases. v1 can be user-scoped; org-scoped publishers are deferred.
- **Buyer:** A user who views listings and initiates installs.
- **Install intent:** A durable record representing a user’s request to install a specific listing/release into a target system.
- **Install token:** An opaque, revocable token derived from an install intent; redeemed by the target system server-side.

---

## 4) System architecture

### 4.1 High-level components
FleetPrompt v1 consists of:
- **Public Marketplace UI**
  - browse/search listings
  - listing detail + release history
- **Publisher Console UI**
  - listing CRUD
  - release publish
  - basic analytics
- **FleetPrompt API**
  - listing/release reads + writes
  - search endpoint(s)
  - install intent creation + token issuance
- **Storage**
  - listings, releases, install intents, publisher profiles, moderation flags
  - append-only audit log for mutations (recommended)
- **Optional integrations**
  - SpecPrompt commerce integration (deferred if you want v1 non-monetized)
  - verification sources (manual verification to start)

### 4.2 Boundaries (hard rules)
FleetPrompt MUST enforce these boundaries:

1) **No runtime execution**
- FleetPrompt never calls model providers, never invokes WHS agents, never runs Agentromatic workflows.

2) **No upstream data mirroring**
- FleetPrompt MUST NOT persist upstream telemetry, execution logs, room transcripts, or tool traces.

3) **No authorization bypass**
- FleetPrompt must not provide endpoints that let a client perform privileged actions in another system.
- All cross-system actions must be redeemed server-side by the owning system with its own authorization checks.

4) **Install is an intent, not proof**
- FleetPrompt may record “install started” or “token issued”.
- FleetPrompt must not claim “install completed” unless the owning system reports it via a secure, authenticated callback (optional, deferred).

### 4.3 Data flows (canonical)
These are normative flows FleetPrompt v1 must support.

#### Flow A — Browse marketplace (signed-out)
1. Client requests `listings.search` or `listings.list`.
2. FleetPrompt returns public listing cards (safe, bounded fields).
3. Client opens `listings.get` for detail.
4. FleetPrompt returns listing + release history (public-only).

#### Flow B — Publisher creates listing
1. Publisher authenticates.
2. Publisher calls `listings.create` with metadata.
3. FleetPrompt validates content (sizes, sanitization).
4. FleetPrompt persists listing with status `draft`.
5. FleetPrompt writes an audit event.

#### Flow C — Publisher publishes a release
1. Publisher calls `releases.publish` with:
   - `listingId`
   - `version` (semver string)
   - upstream references (`whsAgentId`, `agentromaticWorkflowId`, etc.) depending on asset kind
   - optional artifact pointers (only if FleetPrompt hosts artifacts in v1)
2. FleetPrompt validates:
   - version uniqueness per listing
   - bounded fields
   - reference format constraints (opaque strings; no parsing)
3. FleetPrompt persists release as immutable record (recommend: releases are append-only).
4. FleetPrompt writes an audit event.

#### Flow D — Buyer initiates install (handoff)
1. Signed-in buyer clicks “Install” on a listing/release.
2. FleetPrompt creates an `installIntent`:
   - buyer identity
   - listingId + releaseId
   - target system (e.g., `whs|agentromatic|agentelic`)
   - optional target context (e.g., `telespaceId` for Agentelic installs) as opaque strings
3. FleetPrompt returns either:
   - a deep link to target system UI, OR
   - an opaque `installToken` for redemption

4. The target system redeems the install token server-side:
   - validates token with FleetPrompt (or validates a signed token locally if you choose signed tokens)
   - enforces its own authorization (ownership/membership/role checks)
   - performs import/install in its own domain

5. FleetPrompt may record the redemption attempt as an audit entry if a callback is implemented (optional v1).

---

## 5) Product requirements (engineering-focused)

### 5.1 Listings (v1)
Listings MUST have:
- `listingId` (opaque string)
- `publisherId` (tenant owner)
- `assetKind`:
  - `whs_agent` OR `agentromatic_workflow` OR `spec_asset` (optional)
- Public metadata:
  - `name`, `summary`, `description` (safe rendering)
  - `tags[]`, `categories[]` (bounded)
  - `docsUrl?`, `repoUrl?`
  - `images[]` (optional; constrained file types and sizes)
- `status`: `draft | published | unlisted | suspended`
- timestamps (`createdAtMs`, `updatedAtMs`)

Listings MUST support:
- search/filter/sort (MVP: substring + tag filters is acceptable)
- safe markdown or rich text rendering (sanitized)
- moderation flags (internal fields; not leaked)

### 5.2 Releases (v1)
A release MUST be immutable once published (append-only recommended).
Release fields:
- `releaseId`
- `listingId`
- `version` (string; semver recommended)
- `status`: `published | revoked` (revocation is a state, not deletion)
- Upstream references by asset kind:
  - `whs_agent`: `whsAgentId` (+ optional `whsDeploymentId` as a hint; non-authoritative)
  - `agentromatic_workflow`: `agentromaticWorkflowId`
  - `spec_asset` (optional): `specAssetId` or artifact pointer
- Optional compatibility metadata:
  - `minWHSVersion?`, `minAgentromaticVersion?`, etc. (strings)
- Optional artifact pointers (only if FleetPrompt hosts artifacts):
  - `artifactUrl?` (signed/expiring)
  - `sha256?`
- timestamps (`publishedAtMs`)

### 5.3 Install intents and tokens (v1)
FleetPrompt MUST support creating an install intent record and issuing an install token.

**Install intent fields (minimum):**
- `installIntentId`
- `buyerUserId`
- `listingId`, `releaseId`
- `targetSystem`: `whs | agentromatic | agentelic`
- `targetContext` (optional, bounded object with opaque strings):
  - for Agentelic: `telespaceId`, `roomId?`
  - for Delegatic-governed installs later: `orgId?`
- `status`: `created | token_issued | redeemed | expired | canceled`
- timestamps (`createdAtMs`, `expiresAtMs?`)

**Token properties (required):**
- opaque (does not embed secrets or user content)
- revocable (server-side lookup)
- short-lived by default (e.g., 10–60 minutes recommended)
- single-use preferred (redeem transitions to terminal state)

FleetPrompt MUST NOT include secrets or upstream credentials in tokens.

### 5.4 Search and public read safety
Public endpoints MUST:
- enforce strict output shaping (no internal flags, no private notes)
- paginate and cap results
- be resilient to scraping (rate limits + caching + bot controls)

### 5.5 Auditability (recommended baseline)
FleetPrompt SHOULD provide an append-only audit log for:
- listing create/update/status change
- release publish/revoke
- install intent create/token issue
- moderation actions (admin-only)

Audit entries MUST be:
- secret-free
- bounded in size
- immutable (append-only)

---

## 6) Event model (optional v1)
If FleetPrompt introduces internal events, they MUST:
- be derived from durable records (e.g., `installIntentId`)
- be idempotent on retries
- never include raw user secrets

MVP recommendation: keep it synchronous with DB writes and avoid a separate event bus in v1.

---

## 7) API surface (normative pointers)
FleetPrompt v1 SHOULD define stable API shapes with:
- normalized error envelope (stable codes)
- cursor pagination for list endpoints
- idempotency keys on retryable writes:
  - listing create
  - release publish
  - install intent create/token issuance

The detailed contract belongs in:
- `spec_v1/10_API_CONTRACTS.md` (to be created)

---

## 8) Data model (normative pointers)
The authoritative schema belongs in:
- `spec_v1/30_DATA_MODEL_CONVEX.md` (or equivalent storage doc)

Minimum tables/collections:
- `users` (identity mapping)
- `publishers` (or publisher profile fields on user)
- `listings`
- `releases`
- `installIntents`
- `auditLog` (recommended)
- `rateLimitBuckets` or equivalent (implementation detail)

Required invariants:
- listing ownership enforced for writes
- release version uniqueness per listing
- install token single-use or deterministic redemption semantics
- no plaintext secrets in DB

---

## 9) Security requirements (implementation-grade)

### 9.1 Tenant isolation (MUST)
- Every write MUST verify publisher ownership.
- Private reads (publisher console, install intents) MUST be scoped to the authenticated user (or admin).
- Cross-tenant IDs MUST be IDOR-safe:
  - recommended: return `NOT_FOUND` for resources not visible to caller.

### 9.2 Secrets handling (MUST)
FleetPrompt MUST NOT:
- store runtime secrets (provider keys, OAuth tokens, API keys) in listing metadata
- log secret values
- return secret values in error envelopes

### 9.3 Prompt injection posture (MUST, even though FleetPrompt is not a runtime)
FleetPrompt is UGC-heavy; treat listing content as untrusted input.
- Sanitization and safe rendering are mandatory (XSS prevention).
- Never render untrusted HTML.
- If markdown is used, it must be sanitized and have a constrained feature set.

### 9.4 Abuse controls (SHOULD, minimal v1)
FleetPrompt SHOULD implement:
- rate limiting on:
  - search endpoints
  - listing creation and edits
  - release publishing
  - install intent creation
- bot mitigation for public pages (provider/CDN features acceptable)
- upload quotas and strict file validation for images/artifacts

### 9.5 Confused deputy prevention (MUST)
FleetPrompt MUST NOT become a privileged proxy into upstream systems.
- Install redemption MUST be server-side in the target system.
- If FleetPrompt offers any “import into X” convenience, it must still:
  - require user auth in target system
  - re-check authorization at redemption time
  - remain auditable

---

## 10) Observability and retention (v1)
FleetPrompt MUST:
- assign a `requestId` for correlation (or use platform equivalent)
- log only safe, bounded info (no secrets)
- retain security-relevant logs for a minimum period (define in `50_*` doc if created)

FleetPrompt SHOULD:
- maintain aggregate metrics for listings (views, install intent counts) without storing per-user browsing trails beyond what’s necessary.

---

## 11) UI requirements (v1 minimum)
FleetPrompt v1 should ship:
- public marketplace:
  - homepage/category/search
  - listing detail
- publisher console:
  - listings list
  - listing editor
  - releases list/publish flow
- buyer “My installs” or “My tokens” page is optional but recommended for UX.

---

## 12) Testing strategy (minimum viable)
FleetPrompt MUST have tests proving:
- authorization boundaries (publisher A cannot edit publisher B)
- IDOR safety on private resources (install intents)
- XSS safety (listing content sanitization)
- idempotency behavior on retryable writes
- token redemption invariants (single-use / expiry)

The detailed plan belongs in:
- `spec_v1/60_TESTING_ACCEPTANCE.md`

---

## 13) Open questions (must answer before v1 sign-off)
1. Does FleetPrompt host artifacts in v1, or only store pointers to upstream-owned artifacts?
2. What is the install handoff default:
   - deep-link only, or token redemption?
3. Should FleetPrompt integrate with SpecPrompt in v1 (monetized marketplace) or defer to v1.1?
4. Publisher identity model:
   - user-only in v1, or minimal org support?
5. Moderation requirements:
   - do we need takedown workflows and abuse reporting in v1?

---

## 14) Acceptance criteria (definition of done for v1)
FleetPrompt v1 is “done” when all of the following are demonstrably true:

### 14.1 Marketplace works
- A signed-out user can browse/search listings.
- Listing detail pages render safely (no XSS) and show release history.

### 14.2 Publisher flows work
- A signed-in publisher can:
  - create a listing (draft)
  - update listing metadata
  - publish at least one release
  - publish/unlist/suspend (admin or publisher controls per policy)

### 14.3 Install handoff works (end-to-end)
- A signed-in buyer can initiate install for a specific release.
- FleetPrompt issues an install token or deep link.
- The target system can redeem and validate the install intent server-side (at least one integration path proven in staging).
- FleetPrompt does not claim install success unless authoritative confirmation exists (optional).

### 14.4 Security is proven
- Tenant isolation is enforced:
  - publisher A cannot mutate publisher B’s listing/release
  - buyer cannot read another buyer’s install intents/tokens
- IDOR suite passes across all “get by id” endpoints for private resources.
- No secrets appear in logs, errors, or persisted records.

### 14.5 Reference-first boundary is intact
- FleetPrompt stores only references + bounded summaries.
- No upstream telemetry/log mirroring exists in the data model.

---