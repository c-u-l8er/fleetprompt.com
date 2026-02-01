# ADR-0002: Install Handoff via Intents + Tokens (FleetPrompt)
- **Status:** Accepted
- **Date:** 2026-01-31
- **Owners:** Engineering
- **Decision scope:** How FleetPrompt initiates installs into WHS/Agentromatic/Agentelic without becoming a runtime or an authorization bypass.

---

## Context

FleetPrompt is the **marketplace/distribution layer** (Layer 5). It must enable users to take a listed asset (agent/workflow/spec asset) and “install” it into the **owning system**:

- **WHS** owns agents, deployments, invocation, telemetry, limits/billing.
- **Agentromatic** owns workflows, executions, logs.
- **Agentelic** owns telespaces/rooms/messages and installs that reference WHS/Agentromatic.
- **Delegatic** owns org governance/policies (reference-first).

Marketplace UX demands a one-click-ish flow (“Install”), but portfolio boundaries demand:

- FleetPrompt **must not execute** agents/workflows.
- FleetPrompt **must not bypass** target-system authorization (membership/ownership/roles).
- FleetPrompt **must not** store or leak secrets, tokens, or upstream logs.
- All actions must be robust under retries (browser retries, double submits, transient failures).

We need a durable, auditable handoff mechanism that:
- works across multiple target systems,
- is safe under at-least-once delivery,
- is resistant to replay and token leakage,
- does not require the browser to call privileged internal endpoints.

---

## Decision

### 1) FleetPrompt models “Install” as a durable **Install Intent** (normative)

When a user initiates an install from FleetPrompt, FleetPrompt MUST create an `installIntent` record that captures:

- who: `buyerUserId`
- what: `listingId`, `releaseId`
- where/into: `targetSystem` (`whs | agentromatic | agentelic`)
- optional target context (bounded, opaque strings only), e.g.:
  - Agentelic: `telespaceId`, optional `roomId`
  - Delegatic-governed installs later: `orgId`
- lifecycle state: `created | token_issued | redeemed | expired | canceled`
- timestamps: `createdAtMs`, `updatedAtMs`, optional `expiresAtMs`

**Install Intent is not proof of success.** It is only a durable “user requested install” record.

Rationale:
- Durable intent enables auditability and idempotency.
- It separates “user intent” (FleetPrompt) from “side effect execution” (target system).
- It avoids FleetPrompt needing to call target systems directly.

---

### 2) FleetPrompt issues **Install Tokens** derived from intents (normative)

FleetPrompt MUST mint an **install token** for a specific `installIntent`. Tokens MUST be:

- **opaque** (no embedded secrets, no user content, no upstream credentials)
- **short-lived** by default (recommended TTL: 10–60 minutes)
- **revocable**
- **single-use** by default (preferred)

FleetPrompt MUST store either:
- only a **hash** of the token (preferred), or
- an opaque lookup id with no raw token persistence (acceptable)

Tokens MUST have a lifecycle state:
- `issued | redeemed | expired | revoked`

If a new token is issued for the same intent, FleetPrompt SHOULD revoke previous issued tokens for that intent (policy choice; if implemented, must be deterministic and audited).

Rationale:
- Limits blast radius if token leaks.
- Supports operational safety under retries.
- Enables server-to-server redemption without long-lived credentials.

---

### 3) Redemption is **server-to-server** resolution, not browser-driven (normative)

FleetPrompt MUST provide a redemption mechanism where the **target system server** can resolve an install token to the referenced install intent + release refs.

FleetPrompt MUST NOT allow browser clients to redeem tokens in a way that triggers privileged side effects.

#### 3.1 Redemption endpoint semantics (R1 design)
FleetPrompt will support a server-to-server redemption flow:

- Input:
  - `installToken`
  - `targetSystem` (defense-in-depth; ensures token is used for intended destination)

- Output (secret-free):
  - `installIntent` (bounded)
  - minimal listing identity (id + name + assetKind)
  - release identity + references needed to import/install:
    - for `whs_agent`: `whsAgentId` (+ optional `whsDeploymentId` hint)
    - for `agentromatic_workflow`: `agentromaticWorkflowId`
    - for `spec_asset`: `specAssetId` or artifact pointer (if supported)

#### 3.2 Server authentication for internal redemption
The redemption endpoint MUST use the portfolio-standard **server-to-server HMAC scheme over raw request body bytes** with a **timestamp skew window** (mirrors the WHS delegated invocation pattern).

Required headers (MUST):
- `X-WHS-Delegation-Source: <string>`
- `X-WHS-Delegation-Timestamp: <epoch_ms_as_string>`
- `X-WHS-Delegation-Signature: v1=<hex(hmac_sha256(raw_body_bytes, FLEETPROMPT_INTERNAL_REDEEM_SECRET))>`

Verification rules (MUST):
- Verify the signature over the **exact raw request body bytes** before parsing JSON.
- Enforce a timestamp skew window of **±5 minutes**; reject requests outside the window.

Rationale:
- Prevents confused-deputy scenarios.
- Avoids exposing privileged redemption to browser environments.
- Aligns with portfolio patterns (raw-bytes HMAC exists elsewhere).

---

### 4) Target system is responsible for authorization and side effects (normative)

After redemption, the **target system** MUST:

1. authenticate/resolve the end user according to its own rules
2. enforce its own authorization checks (ownership/membership/role)
3. apply its own idempotency at the “install/import” boundary
4. perform the install/import in its own domain

FleetPrompt MUST NOT claim “install completed” unless the target system later sends an authenticated acknowledgment callback (optional, deferred).

Rationale:
- Keeps ownership boundaries clean.
- Ensures runtime/governance systems remain authoritative.
- Prevents marketplace purchase/intent from becoming an authorization bypass.

---

### 5) Idempotency rules (normative)

FleetPrompt MUST implement idempotency for all retryable handoff operations.

#### 5.1 Install intent creation is idempotent
`createInstallIntent` MUST accept an `Idempotency-Key` and dedupe on:

- `(buyerUserId, endpoint, idempotencyKey)` and a request body hash

If the same key is reused with a different payload hash, FleetPrompt MUST return `CONFLICT`.

#### 5.2 Token issuance is idempotent
`issueInstallToken` MUST accept an `Idempotency-Key` and dedupe similarly:

- `(buyerUserId, endpoint, idempotencyKey)` + request hash

This prevents issuing multiple tokens unintentionally under retries.

#### 5.3 Redemption is effectively idempotent
Redemption MUST be safe under retries:
- If token is single-use:
  - first successful redeem transitions token to `redeemed`
  - subsequent redeems MUST fail deterministically (recommended: `NOT_FOUND` to reduce token enumeration)
- If token is not single-use (not recommended):
  - redemption MUST be recorded and rate-limited; a stable dedupe key SHOULD be used

In all cases, the redemption endpoint MUST NOT cause side effects beyond token state transitions and auditing.

---

## Consequences

### Positive
- Preserves portfolio boundaries: FleetPrompt is not a runtime and not an auth oracle.
- Enables great UX: a consistent “Install” interaction that works across multiple targets.
- Robust under retries: idempotent intent creation and token issuance.
- Safer than direct deep linking alone: supports one-click server-side redemption while still enforcing target-system authz.
- Auditable: intents and token issuance/redemption can be logged without storing sensitive payloads.

### Negative / Tradeoffs
- Requires server-to-server auth implementation and operational key management.
- Introduces additional state (intent + token records) and lifecycle complexity.
- Install completion status is not known to FleetPrompt by default; requires optional callback for richer UX.

---

## Alternatives considered

### A) Deep-link only (no intents/tokens)
Pros:
- simplest to implement initially

Cons:
- weak auditability
- no robust retry semantics
- poorer UX for multi-system installs
- cannot support “redeem in target system server-side” flows

Decision: Rejected as the only mechanism; allowed as a fallback UX path.

### B) FleetPrompt directly calls target systems to perform installs
Rejected:
- makes FleetPrompt a privileged proxy (confused deputy risk)
- requires FleetPrompt to hold more secrets/credentials
- violates “install is a handoff” boundary

### C) Signed tokens verified locally by target systems (R2)
Pros:
- no redemption API call back to FleetPrompt (less coupling)

Cons:
- requires key distribution, rotation, revocation strategy across products
- harder to revoke tokens immediately
- higher complexity for v1

Decision: Deferred. May revisit later if coupling becomes a major issue.

---

## Implementation notes (guidance)

### Data model placement
Recommended FleetPrompt tables:
- `installIntents` (buyer-scoped)
- `installTokens` (tokenHash lookup, expiry, status)
- `idempotencyKeys` (or equivalent dedupe ledger)
- `auditLog` (append-only; secret-free summaries)

### Token hashing
If storing hashes:
- Use a modern, stable hash (e.g., SHA-256) over the token bytes for lookup.
- Store only the hash; never store raw token in DB.
- Never log the raw token or token hash in production logs (hash may still be sensitive for enumeration attacks).

### Error strategy for redemption
To reduce token enumeration:
- Prefer returning `NOT_FOUND` for:
  - invalid token
  - expired token
  - revoked token
  - already redeemed single-use token

### Target-system idempotency
Target systems SHOULD use an idempotency key derived from:
- `(installIntentId, targetSystem)` plus any relevant target context
so repeated redemption/install attempts do not duplicate imports.

---

## Acceptance criteria
This ADR is satisfied when:
1. FleetPrompt can create an install intent and issue a token idempotently.
2. A target system server can redeem a token server-to-server and receive:
   - installIntent + release refs (secret-free)
3. Tokens are short-lived and revocable; single-use tokens cannot be replayed.
4. Browser clients cannot call the redemption endpoint successfully.
5. FleetPrompt does not perform side effects in target systems and does not claim “install completed” without explicit target-system acknowledgment.

---

## Related specs
- `project_spec/spec_v1/00_MASTER_SPEC.md` (FleetPrompt core flows and boundaries)
- `project_spec/spec_v1/10_API_CONTRACTS.md` (install endpoints and idempotency headers)
- `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md` (installIntents/installTokens/idempotency ledger)
- `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` (confused deputy and token safety)
- `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md` (IDOR, token replay, and internal endpoint tests)