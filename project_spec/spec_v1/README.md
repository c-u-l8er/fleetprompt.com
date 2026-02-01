# fleetprompt.com — Spec v1 (FleetPrompt Marketplace)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

FleetPrompt is **Layer 5** in the 6-layer WHS ecosystem:
- **Layer 1 — WebHost.Systems (WHS):** agent runtime + deploy/invoke + telemetry + limits/billing
- **Layer 2 — Agentromatic:** workflow definitions + executions + logs + orchestration
- **Layer 3 — Agentelic:** telespaces (rooms/messages/membership) + installs/automations (references)
- **Layer 4 — Delegatic:** org hierarchy + policies + governance (references, deny-by-default)
- **Layer 5 — FleetPrompt (this):** **distribution/marketplace** for agents/workflows/spec assets
- **Layer 6 — SpecPrompt:** commerce/monetization surface (checkout, licensing, bundles)

This folder defines the **v1 specification** for FleetPrompt as the **marketplace/distribution layer**. It is written to align with the portfolio’s hard boundaries, especially:
- “**references, not copies**” between products
- tenancy/authorization enforced at every boundary
- idempotent automation and safe retry semantics

> Important: FleetPrompt v1 is a *marketplace*, not a runtime. It does **not** execute agents or workflows itself.

---

## 0) What FleetPrompt is (canonical definition)

FleetPrompt is a marketplace that enables:
- **Publishers** to list and release:
  - WHS agents (by reference to `whsAgentId` and deployment metadata)
  - Agentromatic workflows (by reference to `agentromaticWorkflowId`)
  - Optional: “packs” (collections) and “templates” (spec assets) that are later monetized in SpecPrompt
- **Buyers** to discover, evaluate, and install assets into:
  - WHS (agents)
  - Agentromatic (workflows)
  - Agentelic (telespace installs)
  - Delegatic (org-governed catalogs)

FleetPrompt is primarily:
- **catalog + discovery + install handoff + reputation signals**
- It is *not* the system-of-record for executions, telemetry, or agent runtime details.

---

## 1) How to use this spec

### 1.1 Normative vs non-normative
- **Normative:** `project_spec/spec_v1/*.md` and `project_spec/spec_v1/adr/*.md`
- **Non-normative:** any scratch docs, notes, or older drafts outside `spec_v1/`

If anything conflicts:
1. `00_MASTER_SPEC.md` (once created) wins for behavior
2. ADRs win for invariants and rationale
3. other docs are implementation guidance

### 1.2 Recommended reading order
1. `00_MASTER_SPEC.md` — scope, glossary, flows, invariants, acceptance criteria
2. `10_API_CONTRACTS.md` — marketplace API shapes, error envelope, pagination, idempotency
3. `30_DATA_MODEL_CONVEX.md` — schema + indexes + access control rules
4. `40_SECURITY_SECRETS_COMPLIANCE.md` — threat model + secrets + anti-abuse + confused deputy posture
5. `60_TESTING_ACCEPTANCE.md` — tests + release gates
6. `adr/*` — “why” behind decisions (immutability, references, entitlements boundaries)

---

## 2) Architectural stance (hard boundaries)

### 2.1 FleetPrompt MUST NOT
- Execute agents (WHS does that)
- Execute workflows (Agentromatic does that)
- Store secrets for runtimes or integrations (secret refs only, if needed at all)
- Copy upstream logs/telemetry/transcripts:
  - no WHS telemetry mirrors
  - no Agentromatic execution logs mirrors
  - no Agentelic room transcripts
- Treat marketplace purchase/ownership as authorization to run anything:
  - runtime permissions remain enforced by the owning system (WHS/Agentromatic/Agentelic/Delegatic)

### 2.2 FleetPrompt MUST
- Be “reference-first”:
  - store stable references to upstream assets (agent/workflow/spec ids)
  - store bounded, secret-free summaries for UX/search
- Enforce tenant isolation:
  - publisher assets belong to a publisher/tenant
  - buyer entitlements are scoped to a buyer/tenant
- Be idempotent on writes that can be retried:
  - listing create/update
  - release publish
  - entitlement issuance (if FleetPrompt issues any entitlements directly)
- Provide a safe install handoff model:
  - either deep-link to owning system UIs, or
  - produce install manifests/tokens that the owning system validates server-side

### 2.3 “Install” is a handoff, not a side effect
FleetPrompt may initiate an install flow, but the authoritative “install result” lives in:
- WHS (`agents`, `deployments`, optional marketplace metadata fields)
- Agentromatic (`workflows`, templates, optional import)
- Agentelic (`installedAgents`, `installedWorkflows`, automations)
- Delegatic (org catalogs/policies controlling visibility)

FleetPrompt should record *an install attempt* only as a reference/audit entry, never as proof of successful install.

---

## 3) v1 scope (engineering-focused)

### 3.1 Marketplace core
- Search/browse listings
- Listing pages with:
  - description, docs links, compatibility metadata
  - version/release history
  - publisher identity and verification badges (informational)
- Publisher console:
  - create listing
  - upload/publish releases (metadata + artifact pointers)
  - view download metrics (aggregated, non-sensitive)

### 3.2 Asset types (v1)
FleetPrompt supports listing these “asset kinds” (by reference):
- `whs_agent`:
  - reference: `whsAgentId`
  - optional: recommended deployment pin metadata (not authoritative)
- `agentromatic_workflow`:
  - reference: `agentromaticWorkflowId`
- `spec_asset` (optional in v1; becomes core in SpecPrompt):
  - reference: `specId` (or artifact id), plus schema versioning

### 3.3 Install UX (v1 minimal)
- Provide an “Install” CTA that does one of:
  1) deep-link user to the owning system UI with the referenced id, or
  2) generate an **install token** that the owning system redeems server-side (recommended when you need one-click installs)

FleetPrompt does not bypass permissions; it can only provide *intent* and *references*.

---

## 4) Identity & tenancy assumptions

Portfolio-wide assumption (v1):
- a shared identity provider exists (e.g., Clerk subject id used across systems)
- each system still enforces its own tenant isolation and authorization checks

FleetPrompt should treat upstream ids as **opaque strings**:
- never parse ids
- never assume an id implies ownership

---

## 5) Security posture (high level)

FleetPrompt is a high-risk surface because it is public-facing and user-generated-content heavy.

FleetPrompt MUST enforce:
- strict input validation (sizes, markdown sanitization, file types)
- anti-abuse controls (rate limits, spam prevention, upload quotas)
- safe rendering (XSS prevention)
- “confused deputy” protections:
  - marketplace actions cannot automatically trigger privileged upstream side effects
  - redemption/install flows must be server-side and membership/ownership checked by the target system
- no secrets in:
  - listing metadata
  - logs
  - error envelopes

---

## 6) What should exist in this spec set (files to be created)

This README expects the following v1 spec documents to exist (create next):

- `spec_v1/00_MASTER_SPEC.md`
- `spec_v1/10_API_CONTRACTS.md`
- `spec_v1/30_DATA_MODEL_CONVEX.md`
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `spec_v1/60_TESTING_ACCEPTANCE.md`

ADRs (minimum recommended):
- `spec_v1/adr/ADR-0001-references-not-copies.md`
- `spec_v1/adr/ADR-0002-install-handoff-not-execution.md`
- `spec_v1/adr/ADR-0003-entitlements-ownership-vs-authorization.md`
- `spec_v1/adr/ADR-0004-ugc-safety-and-sanitization.md`
- `spec_v1/adr/ADR-0005-idempotency-and-dedupe.md`

---

## 7) v1 acceptance criteria (high level)

FleetPrompt v1 is “done” when you can:

1. Create a publisher account (or admin-mark an account as publisher) and create a listing.
2. Publish at least one release for a listing (metadata + artifact reference).
3. Browse/search listings as a signed-out user (read-only).
4. As a signed-in buyer, initiate an install flow that:
   - either deep-links into the owning system UI, or
   - issues a redeemable install token that the owning system validates server-side.
5. Demonstrate strict safety:
   - no XSS via listing content
   - uploads restricted and scanned/validated
   - rate limits prevent obvious scraping/spam
6. Demonstrate tenancy isolation:
   - publisher A cannot edit publisher B’s listings/releases
   - buyer entitlements (if any) are not readable cross-user
7. Demonstrate “no copying”:
   - FleetPrompt does not persist upstream execution logs/telemetry, only references + bounded summaries.

---

## 8) Progress logs (optional convention)
If you maintain engineering logs, keep them outside `spec_v1/` and treat them as non-normative, append-only, and secret-free (same pattern as other portfolio specs).