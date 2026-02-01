# ADR-0003: Internal Redeem Auth Mode (Server-to-Server HMAC over Raw Bytes)
- **Status:** Accepted (v1)
- **Date:** 2026-02-01
- **Owners:** Engineering
- **Decision scope:** Authentication scheme for FleetPrompt’s **server-to-server** install-token redemption endpoint (`POST /v1/internal/install/redeem`) used by target systems (WHS / Agentromatic / Agentelic).

Related docs:
- `fleetprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md` (§6.4.1 Redeem token)
- `fleetprompt.com/project_spec/spec_v1/adr/ADR-0002-install-handoff-intents-tokens.md` (§3.2–§3.3)
- `WebHost.Systems/project_spec/spec_v1/adr/ADR-0008-delegated-invocation-auth.md` (portfolio pattern reference)
- `WebHost.Systems/project_spec/spec_v1/adr/ADR-0004-telemetry-integrity.md` (raw-bytes signing pattern reference)

---

## Context

FleetPrompt “install” is a **handoff**:
- FleetPrompt mints short-lived, opaque install tokens derived from durable install intents.
- Target systems redeem these tokens **server-side** to resolve intent + release references and then apply their own authorization checks and side effects.

The redemption endpoint is a critical confused-deputy boundary:
- It MUST NOT be callable from browsers in any meaningful/privileged way.
- It MUST be robust under retries and safe under token leakage.
- It MUST align with existing portfolio conventions to reduce drift and implementation ambiguity.

FleetPrompt API contracts explicitly allow multiple auth options for internal redemption, but v1 needs a single locked choice.

---

## Decision

FleetPrompt internal redemption (`POST /v1/internal/install/redeem`) MUST use **server-to-server HMAC over the exact raw request body bytes** with a **timestamp skew window**, mirroring the established WHS delegated-invocation pattern.

### Why this decision
- **Matches portfolio precedent:** WHS already uses HMAC-over-raw-bytes + timestamp headers for server-to-server calls.
- **Pragmatic v1:** avoids PKI/cert ops overhead (mTLS) while providing strong request integrity/auth.
- **Framework-safe:** “raw bytes” avoids canonicalization pitfalls and prevents signature bugs.

---

## Normative request authentication (REQUIRED)

### Required headers (MUST)
Target systems calling FleetPrompt MUST send:

- `X-WHS-Delegation-Source: <string>`
- `X-WHS-Delegation-Timestamp: <epoch_ms_as_string>`
- `X-WHS-Delegation-Signature: v1=<hex(hmac_sha256(raw_body_bytes, FLEETPROMPT_INTERNAL_REDEEM_SECRET))>`

Notes:
- Header names intentionally reuse the existing portfolio convention (even though this endpoint is FleetPrompt-owned) to minimize header-scheme drift across products.
- `raw_body_bytes` means the exact bytes on the wire (no JSON parsing or re-serialization before verification).

### Signature algorithm (MUST)
- Algorithm: `HMAC-SHA256`
- Message: `raw_body_bytes`
- Key: `FLEETPROMPT_INTERNAL_REDEEM_SECRET` (secret bytes)
- Encoding: lowercase hex is recommended; verification MUST accept upper or lower hex by normalizing.

Header format:
- `X-WHS-Delegation-Signature: v1=<hex>`

### Timestamp validation (MUST)
- FleetPrompt MUST parse `X-WHS-Delegation-Timestamp` as an integer epoch milliseconds.
- FleetPrompt MUST enforce a skew window of **±5 minutes**.
- Requests outside the window MUST be rejected as `UNAUTHENTICATED` (or `UNAUTHORIZED` if that is the existing FleetPrompt normalized code mapping; pick one and keep it consistent across internal endpoints).

### Verification order (MUST)
For `POST /v1/internal/install/redeem`, FleetPrompt MUST:
1. Read required headers and validate presence.
2. Read the raw request body bytes **once**.
3. Verify the HMAC signature over those raw bytes.
4. Only after successful verification, parse JSON and proceed.
5. If verification fails, FleetPrompt MUST NOT mutate any state (no token state transitions, no audit rows, no counters beyond safe request metrics).

---

## Replay and retry behavior (v1 semantics)

This auth mode provides request authenticity and integrity. Replay resistance is primarily enforced by:
- the timestamp skew window, AND
- token redemption semantics.

Therefore, FleetPrompt MUST ensure redemption is safe under retries/replays:

- Install tokens SHOULD be **single-use** (preferred v1 policy).
- Redemption MUST transition the token to `redeemed` (or equivalently make it unusable).
- Subsequent redemption attempts for the same token MUST fail deterministically without leaking token validity beyond what is necessary.
  - Recommended: return `NOT_FOUND` for expired/revoked/used tokens to reduce enumeration.
  - If `CONFLICT` is used for “already redeemed,” it MUST still be IDOR-safe and not leak cross-tenant existence.

These rules are independent of the HMAC auth and are required to keep the endpoint safe even if a valid internal request is replayed within the timestamp window.

---

## Configuration and key management

### Secret material (MUST)
FleetPrompt MUST load the HMAC key from environment/secret management as:

- `FLEETPROMPT_INTERNAL_REDEEM_SECRET`

Rules:
- The secret MUST be treated as high-sensitivity material.
- FleetPrompt MUST NOT log it, echo it, or persist it in application DB rows.
- Minimum recommended key size: **32 bytes** of randomness (256 bits).

### Source allowlist (SHOULD)
FleetPrompt SHOULD enforce an allowlist for `X-WHS-Delegation-Source` to reduce blast radius and help incident response.

Recommended policy:
- Allow only known portfolio services (e.g., `whs`, `agentromatic`, `agentelic`, `specprompt`).
- Unknown sources SHOULD be rejected with `UNAUTHENTICATED`.

(If/when multi-environment routing exists, allowlisting should be environment-scoped.)

---

## Consequences

### Positive
- Consistent internal auth surface across the portfolio (reduces operational and implementation drift).
- Raw-body signing avoids signature verification bugs caused by JSON parsing/serialization differences.
- Simple v1 operational story (no PKI/cert lifecycle).

### Tradeoffs / limitations
- Timestamp-window HMAC does not provide perfect replay prevention by itself; correctness relies on token single-use semantics and timestamp skew enforcement.
- Secret rotation is non-trivial unless explicitly designed (v1 can start with a single key; rotation can be added later via key IDs or dual-accept windows).

---

## Alternatives considered

### A) mTLS between services
Rejected for v1 due to operational complexity (certificate issuance/rotation, runtime uniformity) across heterogeneous environments.

### B) Static bearer token (private network + Authorization header)
Rejected as least preferred due to easy accidental leakage, weaker request integrity properties, and poorer auditability.

### C) Signed install tokens verified locally (no redemption call)
Deferred (FleetPrompt `R2` design). Requires cross-system key distribution, rotation, and revocation strategy; higher complexity than v1 needs.

---

## Implementation notes (guidance; non-normative)

- Verification must be implemented against the exact bytes received; ensure middleware/framework does not consume the body before signature verification.
- Prefer constant-time comparison when comparing signature material.
- Keep error responses generic and consistent; do not reveal whether signature vs timestamp failed.
- Rate-limit `/v1/internal/install/redeem` per `X-WHS-Delegation-Source` (defense in depth).
