# ADR-0001: References, Not Copies (FleetPrompt marketplace boundary)
- **Status:** Accepted
- **Date:** 2026-01-31
- **Owners:** Engineering
- **Decision Scope:** FleetPrompt data ownership boundaries for listings, releases, installs, and cross-product integrations (WHS / Agentromatic / Agentelic / Delegatic / SpecPrompt)

---

## Context

FleetPrompt is **Layer 5** in the 6-layer ecosystem:
- **WHS (Layer 1)** owns: agent definitions, deployments, invoke gateway, telemetry, limits/billing.
- **Agentromatic (Layer 2)** owns: workflow definitions, executions, execution logs, condition evaluation, snapshotting.
- **Agentelic (Layer 3)** owns: telespaces, rooms, membership, messages, activity timeline (reference-first).
- **Delegatic (Layer 4)** owns: org hierarchy, policies, governance, audit log (reference-first).
- **FleetPrompt (Layer 5)** owns: marketplace discovery, listing metadata, release metadata, install handoff.
- **SpecPrompt (Layer 6)** owns: commerce (checkout, entitlements, fulfillment).

FleetPrompt is public-facing and UGC-heavy. If FleetPrompt copies upstream execution artifacts (telemetry, logs, transcripts), it creates:
- **Data divergence:** multiple “truths” for the same execution/event.
- **Security risk:** logs and telemetry often contain sensitive data or secret-adjacent context.
- **Compliance ambiguity:** unclear retention/deletion obligations when multiple products store the same data.
- **Cost growth:** unbounded log/telemetry mirrors become expensive quickly.
- **Confused deputy risk:** a marketplace that stores and serves runtime details can accidentally become an authorization oracle.

We want FleetPrompt to remain a **distribution layer**, not a runtime or observability system.

---

## Decision

### 1) FleetPrompt stores references, not copies (normative)

FleetPrompt MUST store only:
- **Opaque identifiers** that reference upstream assets, and
- **Bounded, secret-free summaries** needed for marketplace UX (search, listing pages), and
- **Install handoff intents/tokens** that resolve to references (not to runtime data).

FleetPrompt MUST NOT copy or mirror:
- WHS telemetry event streams, metrics time series, trace payloads
- WHS invocation transcripts or tool traces
- Agentromatic executions and execution logs
- Agentelic messages, room transcripts, or activity timelines
- Delegatic audit logs or membership graphs

FleetPrompt remains the source of truth only for:
- listings, releases, publisher profiles (as applicable)
- install intents/tokens (handoff primitives)
- marketplace-level moderation state (bounded, private)
- marketplace analytics that are **aggregate** and **non-sensitive** (e.g., view counts, install-intent counts)

---

### 2) Release metadata is “reference-first” (normative)

A FleetPrompt release MAY include:
- `refs.whsAgentId` (required for `assetKind="whs_agent"`)
- `refs.whsDeploymentId` (optional hint only; non-authoritative)
- `refs.agentromaticWorkflowId` (required for `assetKind="agentromatic_workflow"`)
- `refs.specAssetId` (optional / future; typically fulfilled by SpecPrompt)

Releases MAY include bounded compatibility metadata:
- `minWHSVersion`, `minAgentromaticVersion`, `minAgentelicVersion` (strings)

Releases MAY include bounded notes/snippets for UX:
- release notes markdown (sanitized, size-limited)

Releases MUST NOT embed:
- upstream logs
- telemetry payloads
- large transcripts
- unbounded raw provider payloads

---

### 3) “Install” is a handoff; FleetPrompt is not authoritative for install outcomes (normative)

FleetPrompt MUST treat “install” as an **intent**, not an action performed in FleetPrompt.

- FleetPrompt may create an `installIntent` and mint a short-lived token.
- FleetPrompt may provide a server-to-server redemption endpoint that resolves token → intent + references.
- The **target system** (WHS / Agentromatic / Agentelic) MUST:
  - enforce its own authorization checks, and
  - perform the actual install/import in its own domain.

FleetPrompt MUST NOT claim “install succeeded” unless the owning system reports it via an authenticated callback (optional feature; out of scope for this ADR).

---

### 4) Deeper details are fetched on demand from the owning system (recommended)

If a user needs deep runtime details (telemetry, execution logs), FleetPrompt SHOULD:
- Deep-link to the owning product UI, OR
- Call the owning product API server-side (only if a later ADR explicitly defines a safe proxy model)

FleetPrompt MUST NOT rely on browsers/clients directly calling upstream systems in ways that weaken tenant isolation.

---

## Consequences

### Positive
- Clear ownership boundaries: each subsystem has one source of truth.
- Lower risk of secret leakage (FleetPrompt avoids persisting the most sensitive data classes).
- Lower operational cost (no unbounded log/telemetry mirrors).
- Cleaner compliance story (retention/deletion obligations remain with the owning system).
- Easier evolution: FleetPrompt can list assets from multiple upstream systems without becoming coupled to their data models.

### Negative / Tradeoffs
- Some marketplace UX (e.g., “show runtime performance stats”) is limited unless implemented as:
  - bounded aggregates, or
  - on-demand fetches from owning systems.
- “One-click install confirmation” requires an authenticated callback from the owning system to be authoritative.
- Users may need to navigate to other products for rich “details” views.

---

## Alternatives considered

### A) Copy upstream logs/telemetry into FleetPrompt
Rejected due to:
- high leakage risk
- unclear compliance/retention ownership
- high storage cost and drift risk

### B) Mirror “safe summaries” of telemetry/logs
Deferred. This may be added later only if:
- summaries are strictly bounded,
- secrets are redacted deterministically,
- there is an explicit retention policy,
- and we add an ADR defining authorization and data provenance.

### C) Make FleetPrompt the orchestrator-of-record for installs/executions
Rejected. FleetPrompt is a distribution layer; execution/telemetry belongs to WHS/Agentromatic/Agentelic.

---

## Implementation notes (guidance)

### Data model implications
FleetPrompt tables should store:
- `listings`: metadata + sanitized markdown + tags/categories
- `releases`: `refs` (opaque upstream IDs) + bounded compat + bounded notes
- `installIntents`: buyer + listing/release refs + bounded target context
- `installTokens`: hashed token + TTL + single-use status transitions
- optional `auditLog`: append-only events for marketplace mutations (secret-free)

### Analytics implications
FleetPrompt may store:
- aggregate counts like `views30d`, `installIntents30d`
FleetPrompt must not store:
- per-invocation telemetry
- per-user browsing trails beyond what is necessary for operations/security

### Security notes
- Treat all upstream IDs as opaque; never infer ownership from an ID.
- Install redemption must be server-to-server; browsers must not be able to redeem tokens directly.

---

## Revisit criteria

Revisit this ADR if:
- marketplace UX requires richer performance signals and we can implement them as bounded aggregates,
- product requirements demand “verified install success” (requires authenticated callback protocol),
- new compliance requirements mandate denormalized snapshots (would require a dedicated ADR with retention + redaction guarantees).

---

## Related specs
- `project_spec/spec_v1/00_MASTER_SPEC.md`
- `project_spec/spec_v1/10_API_CONTRACTS.md`
- `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md`
- `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md`
