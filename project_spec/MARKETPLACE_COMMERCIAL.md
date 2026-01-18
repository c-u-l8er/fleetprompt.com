# FleetPrompt Marketplace (Commercial) — Spec
## Accounts + Stripe Connect + Entitlements + Tech Stack (Ash + Phoenix + Inertia + Svelte)

**Status:** Draft (Jan 2026)  
**Scope:** FleetPrompt.com commercial marketplace layer that complements OpenSentience Core (local runtime/governance) and the FleetPrompt Engine (agent).  
**Primary audience:** You (solo founder) + future contributors implementing FleetPrompt Marketplace.

---

## 0) Executive summary

FleetPrompt Marketplace is the **commercial distribution and monetization layer** for portfolio agents (starting with FleetPrompt Engine agents), while OpenSentience Core remains the **local-first governance/runtime**.

This spec locks the following decisions:

1) **Users have accounts** (Marketplace-managed identities).  
2) **Publishers are individuals at first** (future: organizations).  
3) Monetization uses **Stripe Connect (Express)** to support **true marketplace payouts**.  
4) Paid model: **source available** with **paid updates** (plus optional support).  
5) Marketplace stack:
   - **Elixir + Phoenix**
   - **Ash Framework** for domain modeling
   - **Inertia.js** integrated with Phoenix
   - **Svelte** frontend (via Inertia)

Non-negotiable portfolio compatibility:
- Paid does **not** bypass OpenSentience Core’s permission approvals.
- Install/build remains an explicit trust boundary.
- Marketplace controls **entitlements and delivery**, not runtime privileges.

---

## 1) Definitions

- **OpenSentience Core:** Local, always-running governance plane (catalog, enablement, ToolRouter, audit log, launcher). Canonical spec: `opensentience.org/project_spec/agent_marketplace.md`.
- **FleetPrompt Engine (agent):** Workflow/skills engine running as an OpenSentience Agent. Canonical spec: `fleetprompt.com/project_spec/*` and `opensentience.org/project_spec/WORKFLOW_ORCHESTRATION.md`.
- **FleetPrompt Marketplace:** FleetPrompt.com commercial web product. This document.
- **Publisher:** A creator who publishes and sells agents through the marketplace.
- **Listing:** Marketplace page describing an agent (metadata, pricing, versions, docs).
- **Entitlement:** A record granting a buyer rights to install and receive updates for an agent.
- **Artifact:** A downloadable package for a specific agent version (source bundle or build artifact), with integrity metadata (hash/signature).
- **Update eligibility:** Rules determining which versions a buyer can download (e.g., “updates while subscribed”).
- **Connect account:** Stripe Connect Express account representing a publisher for payouts.

---

## 2) Architecture & ownership boundaries (portfolio truth)

FleetPrompt Marketplace must not collapse portfolio boundaries.

### 2.1 What FleetPrompt Marketplace owns
- Accounts (users, publishers)
- Stripe payments + subscriptions
- Stripe Connect onboarding for publishers
- Entitlements issuance + revocation (based on payment state)
- Artifact hosting and authenticated downloads
- Marketplace registry/index (commercial metadata and availability)
- Verification/curation signals (informational)

### 2.2 What FleetPrompt Marketplace does NOT own
- Runtime permission enforcement
- Agent process isolation
- Local install/build trust boundary enforcement
- Tool routing enforcement
- Unified local audit log

Those are Core responsibilities.

### 2.3 How FleetPrompt Marketplace integrates with OpenSentience Core
- Marketplace provides a “commercial registry” and a **download API**.
- OpenSentience Core consumes entitlements and downloads artifacts, but still:
  - requires explicit enablement for permissions
  - audits install/build/enable/run locally
  - treats marketplace metadata as untrusted input

---

## 3) Product goals and non-goals

### 3.1 Goals (v1)
- Ship a usable commercial marketplace as a solo developer.
- Support:
  - user accounts
  - paid agents (one-time and subscriptions)
  - publisher onboarding + payouts via Stripe Connect Express
  - entitlements + download delivery
  - “source available, paid updates” business model
- Keep operational complexity bounded:
  - minimize custom compliance UI (use Stripe-hosted flows where possible)
  - keep the marketplace backend authoritative for entitlements

### 3.2 Non-goals (v1)
- Becoming a full Merchant-of-Record platform with global tax perfection out of the gate.
- Full enterprise org features (SSO, org billing, procurement workflows).
- A “true app store sandbox” runtime model (Core already does isolation and permissions; Marketplace doesn’t add sandboxing).
- A global trust score system (verification is informational initially; see `opensentience.org/project_spec/TRUST_AND_REGISTRY.md`).

---

## 4) Business model: source available + paid updates

### 4.1 What “paid updates” means
A buyer can always install the agent version they’re entitled to, but access to newer versions depends on their entitlement policy:

- **One-time purchase (Major-version license):**
  - grants perpetual access to:
    - the purchased major version line (e.g., `1.x`)
  - no access to major upgrades (e.g., `2.x`) unless purchased separately
  - optional: include “updates for 12 months” instead (only if you want stricter economics)

- **Subscription (Updates while active):**
  - grants access to:
    - all versions released while subscription is active
  - when subscription ends:
    - buyer retains access to the last eligible version
    - no new downloads beyond eligibility

### 4.2 Refunds and chargebacks (policy baseline)
- Refund or chargeback should:
  - revoke entitlement status (no further downloads)
  - not force uninstall on user machines (Core may warn)
- Subscription past_due:
  - temporary grace (configurable)
  - then entitlement becomes inactive until payment recovers

This policy is enforced at the Marketplace entitlement layer.

---

## 5) Payment & payouts: Stripe Connect (Express)

### 5.1 Chosen setup
- **Stripe Connect Express** for publishers
- Platform-controlled checkout (FleetPrompt-branded)
- Marketplace take-rate implemented via:
  - **application fee** on charges
  - payout routed to connected account via Stripe Connect

This is chosen because it minimizes:
- custom KYC UI
- payout engineering
- operational load for a solo developer

### 5.2 Supported purchase types
- One-time purchases (agent license)
- Subscriptions (agent updates/support)

### 5.3 Stripe objects (conceptual)
- `Customer` (per buyer)
- `Product` + `Price` (per listing plan)
- `Checkout Session` or `PaymentIntent` (charge creation)
- `Subscription` for recurring plans
- `Account` (Connect Express publisher account)
- Webhooks for:
  - checkout completion
  - subscription status changes
  - charge disputes/chargebacks
  - refunds

The marketplace backend is responsible for mapping Stripe events → entitlement state transitions.

---

## 6) Accounts and identity

### 6.1 Account types
- **User (buyer):**
  - can browse listings
  - can purchase
  - can view entitlements and download history
  - can see install instructions/token

- **Publisher:**
  - is also a user account
  - can create listings
  - can connect Stripe account
  - can upload releases/artifacts
  - can view sales/subscription metrics
  - can manage listing status (draft/published)

### 6.2 Authentication
- Email + password is acceptable for v1.
- Optional: magic links later.
- Ensure secure session handling and CSRF protections in Phoenix.

### 6.3 Publisher onboarding flow
1) Publisher requests “become a publisher”
2) Marketplace creates Stripe Connect Express onboarding link
3) Publisher completes Stripe onboarding
4) Marketplace marks publisher as “payout-enabled” once Stripe confirms capabilities

---

## 7) Listings and catalog

### 7.1 Listing entity (minimum metadata)
Each listing must bind to a canonical `agent_id` (reverse-DNS) as used by OpenSentience Core manifests.

Listing fields (minimum):
- `agent_id` (string; canonical)
- `name`
- `summary`
- `description` (long)
- `tags` / `integration_points`
- `repository_url` (source available)
- `docs_url`
- pricing options:
  - one-time license price (optional)
  - subscription price(s) (optional)
- current stable version
- publisher identity (display)
- verification badge (optional; informational)

### 7.2 Relationship to the agent manifest
The agent manifest (`opensentience.agent.json`) remains the canonical source for:
- requested permissions
- entrypoint
- base metadata needed for local discovery/install

Marketplace listing is additional commercial metadata and must not be trusted for runtime authorization.

---

## 8) Releases, artifacts, and delivery

### 8.1 Artifact format (recommended)
To keep Core installs deterministic and auditable, each paid release should ship as:
- a source bundle (tar.gz/zip) or build artifact, plus
- integrity metadata:
  - `sha256`
  - optional signature (future)

### 8.2 Release entity
A release is tied to:
- `agent_id`
- `version` (semver)
- artifact(s)
- release notes
- minimum Core runtime version (optional)
- eligibility policy tags (e.g., major version)

### 8.3 Download authorization
Download endpoints must require:
- authenticated user session (Marketplace account), and
- an active entitlement for the requested agent/version

### 8.4 Core install token (UX)
Marketplace should expose a stable “install token” or “entitlement token” that a user can paste into OpenSentience Core UI/CLI.

Properties:
- token must be revocable
- token must not embed secrets that can be reused indefinitely without server checks (preferred: opaque token with server lookup)
- Core stores it file-backed under `~/.opensentience/` and never in SQLite

---

## 9) Entitlements model

### 9.1 Entitlement states
- `active`
- `inactive` (expired/canceled)
- `past_due` (grace)
- `revoked` (refund/chargeback/admin action)

### 9.2 Entitlement policies
- `one_time_major`:
  - grants access to versions matching `major = purchased_major`
- `subscription_updates`:
  - grants access while subscription active, and may freeze access at last eligible version on cancel

### 9.3 Entitlement transitions (webhook-driven)
- On successful one-time payment:
  - create/activate entitlement
- On subscription created/paid:
  - activate/continue entitlement
- On subscription past_due:
  - set entitlement to `past_due` (optional grace)
- On subscription canceled/ended:
  - set to `inactive` after period end
- On refund/chargeback:
  - set to `revoked`

All transitions should be auditable in the Marketplace system.

---

## 10) Security posture (commercial layer)

### 10.1 Threat model highlights
- Leaked entitlement tokens
- Unauthorized downloads of artifacts
- Publisher impersonation
- Malicious artifact upload
- Webhook spoofing

### 10.2 Controls
- Stripe webhook signature verification
- Token rotation/revocation
- Rate limit download endpoints
- Immutable release artifacts (no “replace in place”; publish new version)
- Publisher identity checks via Stripe onboarding (not a full security audit)
- Optional: signed artifacts in later phases

### 10.3 Relationship to OpenSentience Core security
Marketplace does not weaken Core:
- Core still requires enablement approvals for permissions.
- Core still treats build as a trust boundary.
- Core still isolates processes and audits actions.

---

## 11) Observability and audit (Marketplace side)

Marketplace should record events (server-side) for:
- payments and entitlement changes
- artifact uploads/releases
- download requests (bounded metadata; do not log secrets)

This is separate from OpenSentience Core’s local audit log. Do not attempt to merge them in v1; only ensure Core can show provenance (“installed from FleetPrompt Marketplace listing X, release Y”).

---

## 12) Tech stack spec: Ash + Phoenix + Inertia + Svelte

### 12.1 Backend
- **Elixir**
- **Phoenix**
- **Ash Framework** as the domain modeling layer:
  - resources for Users, Publishers, Listings, Releases, Entitlements, Downloads, Stripe events
  - policies/authorization
  - actions and validations

### 12.2 Frontend
- **Inertia.js** integrated with Phoenix
- **Svelte** as the Inertia frontend renderer

High-level goal:
- Use Phoenix for routing/controllers
- Use Inertia to render SPA-like pages without a separate API-first frontend
- Keep development velocity high (solo dev friendly)

### 12.3 Suggested Ash resources (initial set)
- `Accounts.User`
- `Accounts.Session` (or Phoenix auth integration)
- `Publishers.Publisher`
- `Marketplace.Listing`
- `Marketplace.Release`
- `Marketplace.Artifact`
- `Billing.StripeAccountLink`
- `Billing.StripeEvent`
- `Entitlements.Entitlement`
- `Entitlements.DownloadGrant` (optional)
- `Analytics.Download` (bounded)

### 12.4 Permissions/authorization model (Marketplace)
- Users can only view their own entitlements/download history.
- Publishers can only manage their own listings/releases.
- Admin role (you) can:
  - feature/curate listings
  - revoke entitlements for fraud
  - handle disputes

Authorization should be enforced at the Ash policy layer.

---

## 13) Core integration requirements (OpenSentience)

FleetPrompt Marketplace must support OpenSentience Core with:

1) **Registry metadata**
- A machine-readable index of commercial listings and available versions:
  - list of `agent_id`, latest version, source repo, artifact download endpoints
  - verification badges (informational)
  - expected manifest hash (optional but recommended)

2) **Entitlement verification**
- Endpoint for Core to verify a token and fetch eligible versions
- Must be rate-limited and secret-safe

3) **Artifact downloads**
- Authenticated download endpoints
- Support resumable downloads if possible (nice-to-have)

4) **Revocation**
- If entitlement revoked, Core should no longer be able to download updates

Core-side behavior remains:
- install/build/enable/run workflow
- explicit approvals
- audit log

---

## 14) MVP scope (suggested)

### MVP 0 — Marketplace skeleton
- accounts + login
- browse listings + listing detail pages
- publisher onboarding flow (Stripe Connect Express)
- create listing (draft)

### MVP 1 — One-time purchase + entitlement + download
- checkout for one-time license
- webhook → entitlement
- artifact upload + release publishing
- download gated by entitlement
- basic “install token” UX

### MVP 2 — Subscriptions
- subscription checkout
- entitlement active while paid
- downgrade on cancel/end

### MVP 3 — Publisher dashboard
- revenue stats (basic)
- manage versions/releases
- support links and docs

---

## 15) Open questions (must resolve before implementation)
1) Tax strategy at launch:
   - restrict to certain geos initially, or
   - adopt Stripe Tax early
2) Artifact format and verification:
   - source bundle only first, or include prebuilt artifacts?
3) Entitlement token shape:
   - opaque server-stored tokens (recommended) vs signed JWTs
4) Version eligibility rules:
   - major-line only vs time-based update window vs both
5) Publisher content policy:
   - what is allowed to be “paid”
   - minimum quality gates
   - takedown/dispute process

---

## 16) Acceptance criteria (v1)
- Users can create accounts and purchase an agent.
- Publishers can onboard via Stripe Connect Express and receive payouts.
- Entitlements are created/updated via Stripe webhooks.
- Downloads are gated by entitlements.
- Paid does not bypass OpenSentience Core’s permission approvals or trust boundaries.
- Marketplace remains operationally manageable for a solo developer.

---