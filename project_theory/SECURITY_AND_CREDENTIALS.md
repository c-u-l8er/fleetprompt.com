# FleetPrompt — Security and Credentials Strategy
Last updated: 2026-01-06

This document defines FleetPrompt’s security posture and the credential encryption strategy required for an integration-first, multi-tenant automation platform.

It is written to be actionable for the current stack:
- Phoenix (controllers/plugs)
- Ash + AshPostgres (resources, policies, multitenancy)
- Oban (async jobs)
- Postgres schema-per-tenant (org_<slug>)
- Inertia + Svelte frontend (server-driven SPA)
- Deployed on Fly.io

---

## 1) Goals (what “secure” means here)

FleetPrompt must be safe in these ways:

1. **Zero cross-tenant data leaks**
   - Tenant isolation is existential.

2. **Credential confidentiality**
   - OAuth refresh tokens, access tokens, API keys, and webhook secrets must be protected at rest and in logs.

3. **Operational auditability**
   - We must answer: who did what, when, under what tenant, and what external scopes were used.

4. **Least privilege by design**
   - Minimize the scopes and permissions each integration package requires.
   - Support revocation and rotation without breaking tenant state.

5. **Replay-safe and log-safe observability**
   - Signals and logs are durable; they must never contain raw secrets.

---

## 2) Threat model (what we defend against)

### 2.1 Primary threats
- **Cross-tenant access via bugs**
  - Wrong tenant context in controller/job
  - Unsafe “tenant override” parameters
  - Admin tooling selecting arbitrary tenant

- **Credential disclosure**
  - Tokens stored unencrypted in DB
  - Tokens printed in logs/errors
  - Tokens embedded in signals/events
  - Leaky backups or DB dumps

- **Webhook spoofing**
  - Forged webhook requests
  - Replay attacks
  - Signature verification bypass

- **Account takeover**
  - Weak password handling
  - Session fixation
  - CSRF issues on state-changing endpoints

- **Abuse / cost explosions**
  - Unbounded LLM calls
  - Integration rate-limit blowups
  - Prompt injection causing unintended actions

### 2.2 Non-goals (for early phases)
- Full compliance posture (SOC2/HIPAA) out of the gate
- Multi-region key escrow / HSM requirements
- Arbitrary third-party package code execution (must be deferred until sandboxing exists)

---

## 3) Data classification (what is sensitive)

### 3.1 Highly sensitive (never log; encrypt at rest)
- OAuth refresh tokens and access tokens
- API keys (both FleetPrompt keys and third-party tokens)
- Webhook signing secrets
- Password reset tokens, email verification tokens
- Any secret used to sign/encrypt payloads

### 3.2 Sensitive (avoid logs; encrypt or hash at rest)
- PII (email addresses, names) depending on tenant requirements
- Message contents from external sources if they may contain PII
- Internal correlation IDs can be logged (they’re not secrets)

### 3.3 Non-sensitive
- Package registry metadata
- Public marketing content
- Aggregated usage metrics (if de-identified)

---

## 4) Multi-tenancy security invariants (schema-per-tenant)

### 4.1 Tenant context must be derived server-side
**Rule:** Tenant selection must never be accepted from untrusted client input (headers, query params, body) for privileged operations.

Allowed tenant derivations:
- Browser UI: from the authenticated session’s selected organization (membership-gated)
- API: from API key → organization → tenant schema
- Jobs: from job args that were created by trusted server code (and validated)

### 4.2 Defense-in-depth against tenant bugs
Even with schema-per-tenant, enforce:
- Ash policies that constrain access by org membership where applicable
- Controller/plug invariants: `current_user`, `current_org`, `ash_tenant` must match
- Job invariants: jobs must verify tenant exists and directive/installation belongs to it before acting

### 4.3 No “global admin” bypass by default
If a platform admin concept exists later:
- It must be explicit and audited
- It must not become a backdoor to tenant data without a strong reason

---

## 5) Credential storage model (recommended)

### 5.1 Introduce a dedicated credential resource
Create a tenant-scoped resource (recommended name):
- `FleetPrompt.Integrations.Credential` (tenant schema)

This resource represents a binding between:
- a tenant (`org_<slug>`)
- a package installation (or integration instance)
- a provider (mattermost/proton_mail/shopify/…)
- an account identity (e.g., mattermost_user_id / mattermost_server_id, proton_account_id / bridge_instance_id, store_id)
- scopes and metadata

### 5.2 What to store
Store:
- provider identifier (e.g., `:mattermost`, `:proton_mail`, `:shopify`)
- external account identifiers (e.g., server_id, team_id, channel_id, proton_account_id, bridge_instance_id, store_id)
- granted scopes/roles (string list, when applicable; e.g., Mattermost PAT roles)
- token expiration timestamps (when applicable)
- encrypted credential material (see encryption section) — e.g., Mattermost incoming webhook URL, Mattermost PAT, Proton Bridge credentials/config
- status (active/revoked/expired)

Do NOT store:
- raw tokens in plaintext
- tokens in signals or execution logs

### 5.3 Where to store credentials (tenant vs public schema)
Default: store credentials in tenant schema because:
- they are tenant-owned operational data
- they simplify per-tenant export/restore
- they reduce accidental cross-tenant query risk

Exception: if a future shared-schema tier is introduced, this will need to be revisited.

---

## 6) Encryption strategy (at rest)

### 6.1 Approach: envelope encryption (recommended)
Use envelope encryption for sensitive fields:
1. Generate a random per-record **data encryption key (DEK)**.
2. Encrypt token material with DEK using AEAD (e.g., AES-256-GCM).
3. Encrypt the DEK with a **key encryption key (KEK)** managed outside the database (KMS or equivalent).
4. Store:
   - ciphertext (token data)
   - encrypted DEK
   - algorithm/version metadata

This provides:
- rotation of KEK without rewriting all data
- clear crypto agility
- blast-radius reduction if DB is leaked

### 6.2 MVP alternative: application-managed encryption key (acceptable short-term)
If KMS isn’t ready immediately:
- use a single application-managed key loaded from Fly secrets
- encrypt fields with AEAD (AES-GCM or XChaCha20-Poly1305)
- version the encryption scheme in the stored record

This is acceptable for early phases, but you should plan a migration path to KMS-backed envelope encryption.

### 6.3 Implementation options in Elixir
Recommended direction (choose one and standardize):
- Use a field-level encryption library suitable for Ecto (e.g., Cloak-style encrypted fields) and ensure:
  - keys are sourced from runtime secrets
  - rotation is supported (keyring)
  - ciphertext is authenticated (AEAD)

Regardless of library:
- store encryption version (`enc_v`) and algorithm metadata
- never re-encrypt on read; only on write/rotate flows

---

## 7) Key management (KEK) and rotation

### 7.1 Key sources
- **Fly secrets** should store:
  - base secret(s) used for encryption in MVP
  - signing secrets for webhooks
  - application secret_key_base

Long-term recommended:
- managed KMS (AWS/GCP/Azure) to store KEK(s)

### 7.2 Key rotation requirements
Define a rotation playbook:
- rotate KEK (or app key) on schedule or incident
- support multiple active keys for decryption (keyring)
- new writes use newest key; old ciphertext remains decryptable
- implement a background “re-encrypt” migration only when needed

### 7.3 Separation of keys (critical)
Do not reuse the same secret for:
- session signing/encryption
- credential encryption
- webhook signing
- API key hashing pepper

Use distinct secrets for each purpose.

---

## 8) Hashing strategy (API keys and other secrets)

### 8.1 FleetPrompt API keys
Requirements:
- API keys must never be stored in plaintext.
- Store:
  - `key_prefix` (first N chars) for identification
  - `key_hash` (secure hash)
  - scopes
  - last_used_at
  - expires_at

Hash scheme recommendation:
- Use a keyed hash (HMAC-SHA256) with a server-side pepper OR a strong one-way hash with salt.
- Prefer a constant-time compare on verification.

### 8.2 Passwords
- Use bcrypt (already in deps) with appropriate cost.
- Never log passwords.
- Rate limit login attempts per IP/user.

---

## 9) Webhook security (inbound)

### 9.1 Verification and replay protection
Each inbound webhook integration must implement:
- signature verification using a per-tenant/per-installation signing secret
- timestamp tolerance window (e.g., ±5 minutes) when provider supports it
- request body hash verification
- dedupe based on provider event id → stored as `signals.source_event_id`

### 9.2 Processing pattern
Webhook handler should:
1. Verify signature
2. Normalize payload → emit `signal` (persisted) with:
   - `source = "webhook:<provider>"`
   - `source_event_id = <provider event id>`
   - `dedupe_key` derived if needed
3. Enqueue durable processing (Oban)
4. Return quickly (avoid long request times)

---

## 10) Outbound webhooks (FleetPrompt → customer)

FleetPrompt outbound webhooks (Phase 5+) must:
- sign payloads (HMAC) with per-webhook secret
- include unique event id
- include timestamp
- support retries with backoff and a delivery log
- be idempotent for the receiver

Never include credential material in webhook payloads.

---

## 11) Logging, signals, and redaction

### 11.1 Zero secrets in logs
Mandatory:
- redact tokens, Authorization headers, cookies, CSRF tokens, and any secret-like strings
- sanitize errors before logging external HTTP request/response bodies

### 11.2 Zero secrets in signals
Signals are durable and replayable. Therefore:
- signals must never contain raw credentials
- signals may reference credential IDs, installation IDs, and provider account IDs
- implement a guard in the Signal emit pipeline:
  - reject payloads containing known secret fields (`access_token`, `refresh_token`, `authorization`, etc.)
  - reject non-JSON-safe structures

### 11.3 Correlation IDs everywhere
Signals and directives should carry:
- `correlation_id`
- `causation_id`
- optional trace ids

This improves debugging without exposing sensitive data.

---

## 12) Authorization model (minimum standard)

### 12.1 Role gating for directives and credentials
Baseline:
- only org roles `owner` and `admin` can:
  - add/remove integration credentials
  - request directives (install/upgrade/enable/disable/uninstall)
  - view sensitive operational logs if classified

Members can:
- view normal execution results (depending on tenant preference)
- run “safe” workflows (configurable later)

### 12.2 Principle: no silent side effects from chat
Chat actions must:
- propose typed actions
- require explicit user confirmation for side effects (install, enable integration, send message, etc.)
- map to directives for auditability

This is both a security and product trust requirement.

---

## 13) Rate limiting and abuse controls (security meets unit economics)

Implement rate limits at multiple layers:
- per-org
- per-api-key (Phase 5)
- per-integration credential (provider-level fairness)
- per-endpoint/operation class (webhook ingest vs execution vs install)

Additionally:
- cap LLM usage per org/package plan
- require explicit enablement for expensive operations
- implement circuit breakers for flaky external APIs

---

## 14) Package trust model (security implications)

### 14.1 Default: curated packages only (early)
Until there is a full sandbox and trust system:
- only publish packages controlled by FleetPrompt
- treat “package definitions” as metadata/config/templates, not untrusted code execution

### 14.2 If/when third-party publishing exists
Before enabling:
- signed package releases
- static analysis of package manifests
- explicit permission declarations
- tenant admin approval flow
- strong rollback story

Do not ship “third-party package code execution” without a sandbox boundary.

---

## 15) Schema-per-tenant scaling risks (security + reliability)

Schema-per-tenant is a correct choice early, but security requires migration tooling:
- migration status tracking per tenant
- safe retry and partial failure handling
- ability to quarantine a broken tenant migration without affecting others

Security angle:
- broken migrations often cause “temporary workarounds” that introduce bypasses
- invest early in deterministic migration workflows and idempotency

---

## 16) Incident response and operational readiness (minimum)

Before onboarding real customers with integrations:
- document a key rotation procedure
- document token revocation steps per provider
- ensure logs do not contain secrets (test this)
- have a “disable integration” directive and kill-switch capability per tenant

---

## 17) Implementation checklist (near-term, actionable)

### Phase 2A–2B (packages + signals/directives)
- [ ] Create tenant-scoped `Credential` resource for integrations
- [ ] Add field-level encryption for credential secrets
- [ ] Add “secret redaction” guards to:
  - signal emission
  - logging of external HTTP
- [ ] Enforce role gating for directives + credential management
- [ ] Add dedupe keys for webhook-derived signals
- [ ] Add retention policy for signals (30 days) and cleanup job

### Phase 4 (execution)
- [ ] Add per-execution audit fields and correlation IDs
- [ ] Store tool calls without secrets
- [ ] Add per-org quotas and rate limiting
- [ ] Add circuit breakers for external calls

### Phase 5 (API)
- [ ] API keys stored hashed only; no plaintext keys
- [ ] API auth derives tenant context from key → org
- [ ] Add rate limiting per key/org
- [ ] Signed outbound webhooks with retries and delivery logs

---

## 18) Definition of “secure enough to ship integrations”
You can begin onboarding design partners with integrations when:
- credentials are encrypted at rest
- no secrets appear in logs or signals (validated)
- directives and installs are audited and replayable
- tenant boundaries are enforced at every edge (UI/API/jobs)
- webhook verification and replay protection are implemented for at least one provider

---