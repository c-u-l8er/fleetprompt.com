# FleetPrompt — Phase 2D: Proton Mail Edge Connector (Bridge-based)
File: `fleetprompt.com/project_plan/phase_2d_proton_mail_edge_connector.md`  
Status: Spec (new)  
Last updated: 2026-01-06

## 0) Purpose

Proton Mail is a privacy-first email provider. Unlike many email systems, Proton Mail does **not** expose a simple cloud-hosted IMAP inbox for third-party SaaS access. Proton’s documented approach for IMAP/SMTP interoperability is **Proton Mail Bridge**, which runs locally and exposes IMAP/SMTP to mail clients.

Therefore, FleetPrompt’s Proton Mail integration must be implemented as an **edge connector**: a customer-controlled process that runs near Proton Mail Bridge and securely communicates with FleetPrompt.

This document specifies that edge connector: what it does, how it authenticates, what it sends, what it stores, how it stays secure, and how it maps to FleetPrompt’s platform primitives (**signals + directives + executions**).

---

## 1) Non-goals (explicit)

Phase 2D does **not** attempt to:
- bypass Proton’s Bridge requirement,
- scrape Proton web UI,
- impersonate a human mail client beyond normal IMAP/SMTP usage through Bridge,
- implement a full “email client” UI,
- provide universal OAuth-based “cloud connect” for Proton Mail (assume Bridge/edge is required),
- implement complex multi-user shared mailbox semantics out of the gate.

Phase 2D also does **not** require FleetPrompt to store full email bodies by default. The default posture is minimal data retention with explicit opt-in expansion.

---

## 2) High-level architecture

### 2.1 Components

- **Proton Mail Bridge** (customer environment)
  - Exposes local IMAP/SMTP endpoints to mail clients.
  - Provides access to Proton mailbox contents via IMAP and allows sending via SMTP.

- **FleetPrompt Edge Connector** (customer-controlled process)
  - Connects to Proton Mail Bridge via IMAP (ingest) and SMTP (send) where needed.
  - Normalizes inbound/outbound events into FleetPrompt **Signals**.
  - Receives FleetPrompt **Directives** (optional early; required later).
  - Performs safe retries and enforces idempotency locally.

- **FleetPrompt Cloud** (fleetprompt.com)
  - Receives edge-emitted signals and persists them in the tenant schema (`org_<slug>.signals`).
  - Routes signals to handlers/jobs (Oban).
  - Tracks directives and execution logs; emits outcomes.

### 2.2 Data flow

#### Inbound (email → signals)
1) Bridge exposes IMAP.
2) Edge connector polls IMAP for new/changed messages or uses IMAP IDLE (if feasible/reliable).
3) Edge connector normalizes the message to a canonical internal event:
   - does **not** send secrets,
   - does **not** send full bodies unless explicitly configured.
4) Edge connector POSTs a **Signal** to FleetPrompt cloud:
   - `email.inbound.received` (and optionally follow-up classification signals).

#### Outbound (directives → email send)
1) FleetPrompt creates a **Directive** like `email.send` for a tenant (role-gated).
2) FleetPrompt delivers the directive to the edge connector (pull or push).
3) Edge connector sends mail via Bridge SMTP and reports results:
   - `email.outbound.sent` or `email.outbound.failed`.

---

## 3) Deployment model

### 3.1 Who runs the connector?
The customer runs it. Options (all valid):
- on the same machine as Proton Mail Bridge,
- on a server in the same network where Bridge is reachable,
- in a container on an on-prem host (if Bridge is accessible),
- on a workstation (less ideal but acceptable for small teams).

### 3.2 Packaging options
- A standalone binary (preferred long-term for simplicity).
- A container image (requires Bridge connectivity; not always trivial).
- A “desktop agent” style installer (future).

### 3.3 Operational requirement
The edge connector must be designed to survive:
- intermittent network connectivity to FleetPrompt cloud,
- Bridge restarts,
- IMAP transient errors,
- local machine restarts.

It must also provide enough logging (locally) for troubleshooting without leaking secrets.

---

## 4) Tenancy and identity model

### 4.1 Tenant binding
The connector must bind to exactly one FleetPrompt Organization (tenant) per configured profile, unless explicitly configured for multi-tenant.

Each connector profile includes:
- `fleetprompt_base_url` (e.g. `https://fleetprompt.com`)
- `tenant_schema` or `organization_id` (preferred: org id; tenant schema derived server-side)
- `connector_id` (UUID generated client-side; stable per installation)
- `device_id` (stable per device; may equal connector_id)
- `connector_secret` or `api_key` for authenticating to FleetPrompt

### 4.2 Authentication (edge → FleetPrompt)
The connector authenticates to FleetPrompt using a **tenant-scoped integration API key**.

Requirements:
- API key must be revocable.
- API key must be scope-limited (example scopes):
  - `signals:write`
  - `directives:read` (if connector pulls directives)
  - `email:send` (if connector sends mail)

The connector never accepts tenant identifiers from remote instructions without validation. Tenant context is derived from the API key binding server-side.

---

## 5) Connector configuration

### 5.1 Minimal required configuration
- Proton Bridge IMAP host/port (often local; configurable)
- Proton Bridge SMTP host/port (often local; configurable)
- Proton Bridge credentials for IMAP/SMTP (stored locally in secure storage)
- FleetPrompt base URL
- FleetPrompt API key / connector auth secret
- Mailbox selection rules:
  - which folders to monitor (e.g., INBOX)
  - which labels to treat as “processed”
- Polling/IDLE strategy:
  - `poll_interval_seconds` (default e.g. 30–60s)
  - optionally enable IMAP IDLE if stable in the environment

### 5.2 Optional configuration (recommended)
- Data minimization mode:
  - `send_body: false` (default)
  - `send_snippet: true/false` (default true with max length)
  - `send_headers: allowlist` (From/To/Subject/Date/Message-ID)
- Attachment handling:
  - `attachment_mode: none | metadata_only | upload` (default `metadata_only` or `none`)
- Sender restrictions:
  - `allowed_from_addresses` allowlist (outbound)
- Safety rules:
  - `max_messages_per_minute` to protect Bridge and FleetPrompt
  - `max_payload_size_bytes`
- PII redaction:
  - whether to hash email addresses in signals (default: send clear emails to FleetPrompt because it’s operationally required, but do not store bodies)

---

## 6) Security requirements

### 6.1 Secret handling
- Bridge IMAP/SMTP credentials are stored locally only.
- FleetPrompt API key is stored locally only.
- No credentials are ever included in:
  - FleetPrompt Signals,
  - FleetPrompt logs,
  - connector outbound payloads.

### 6.2 Local secret storage
Implementation should use OS-appropriate secure storage:
- macOS Keychain
- Windows Credential Manager
- Linux secret service / keyring (or encrypted file as fallback)

### 6.3 Transport security
All connector-to-FleetPrompt traffic must use TLS.

### 6.4 Replay protection and idempotency
The connector must implement dedupe:
- do not emit duplicate inbound message signals for the same email
- do not send duplicate outbound emails for retried directives

### 6.5 Least privilege
Use a dedicated Proton Bridge account configuration if possible (and dedicated SMTP identity), and restrict outbound sending to allowlisted sender addresses.

---

## 7) Signal contract (edge → FleetPrompt)

The connector emits **persisted signals** into FleetPrompt tenant schema.

### 7.1 Required signal fields
- `type` (string)
- `source` (string) — e.g. `edge:proton_mail`
- `occurred_at` (timestamp)
- `subject_type` / `subject_id` (optional but recommended)
- `data` (JSON map)
- `metadata` (JSON map) including:
  - `schema_version: 1`
  - `correlation_id`
  - `causation_id` (if derived from a directive)
  - `connector_id`
  - `device_id`
  - `account_id` (proton account identity reference if available)
  - `dedupe_key` (or use top-level `dedupe_key`)

### 7.2 Signal types (v1)
Inbound:
- `email.inbound.received`
- `email.inbound.processed` (optional; when FleetPrompt confirms workflow completion)
- `email.inbound.failed` (only for connector-level failures that block ingestion; do not include bodies)

Outbound:
- `email.outbound.requested` (optional; emitted when directive is pulled/accepted)
- `email.outbound.sent`
- `email.outbound.failed`

Connector health:
- `connector.heartbeat`
- `connector.error`

### 7.3 Dedupe key scheme (critical)
Inbound message dedupe:
- Prefer a stable message identifier from headers:
  - Message-ID (if present)
- Also include IMAP UID + folder as fallback.

Recommended:
- `dedupe_key = "email_in:{tenant}:{connector_id}:{folder}:{imap_uid}:{message_id_hash}"`

Outbound send dedupe:
- Use directive idempotency key or directive id:
  - `dedupe_key = "email_out:{tenant}:{directive_id}"`

---

## 8) Email payload shape (data minimization first)

### 8.1 Default payload (no full body)
For `email.inbound.received`, `data` should include:

- `message`:
  - `message_id` (string | null)
  - `imap_uid` (string | int)
  - `folder` (string)
  - `internal_date` (timestamp)
  - `from` (string) — email address (or structured object)
  - `to` (array of strings)
  - `cc` (array of strings)
  - `subject` (string | null)
  - `snippet` (string | null) — short snippet, length-limited
  - `headers` (map) — allowlisted headers only
- `flags`:
  - `seen` (bool)
  - `answered` (bool)
  - `flagged` (bool)
- `attachments`:
  - list of attachment metadata only:
    - filename
    - content_type
    - size_bytes

### 8.2 Optional payload expansions
Only if tenant opts in:
- `body_text` (string, truncated) OR
- `body_html` (string, truncated) OR
- attachments uploaded to FleetPrompt (future; requires signed upload URLs and strict scanning)

---

## 9) Directive handling (FleetPrompt → edge)

Phase 2D can start with **inbound-only** (signals only) and add outbound later. However, the “full communication triangle” requires outbound email, so we specify it here.

### 9.1 Directive delivery mechanism options
Option A (recommended v1): **Pull model**
- Edge connector periodically polls FleetPrompt for pending directives for this connector.
- Pros: simpler networking (no inbound port needed)
- Cons: polling latency

Option B (later): **Push model**
- FleetPrompt sends directives to the connector via a customer-exposed endpoint or via an established tunnel.
- Pros: low latency
- Cons: networking complexity

### 9.2 Directive types (email)
- `email.send`
  - params:
    - `from` (string)
    - `to` (array of strings)
    - `cc` (array of strings, optional)
    - `bcc` (array of strings, optional)
    - `subject` (string)
    - `text_body` (string, optional)
    - `html_body` (string, optional)
    - `reply_to_message_id` (string, optional)
    - `idempotency_key` (string, required)

### 9.3 Directive execution requirements
- Validate required params.
- Enforce local policy (allowed from addresses, rate limit).
- Send via SMTP through Bridge.
- Emit `email.outbound.sent` or `email.outbound.failed` signal with:
  - safe error kind and message,
  - no raw SMTP transcripts,
  - no credentials.

---

## 10) Connector health and observability

### 10.1 Heartbeats
Emit `connector.heartbeat` signal periodically, including:
- connector version
- uptime
- last successful IMAP poll timestamp
- last successful signal post timestamp
- queue backlog size (if any)

### 10.2 Local logs
Local logs must:
- include correlation_id / connector_id
- avoid logging secrets
- be structured where possible
- support debug mode toggles

### 10.3 Failure taxonomy
Normalize errors into:
- `auth` (bad credentials, revoked)
- `network` (cannot reach Bridge or FleetPrompt)
- `rate_limit` (local throttles)
- `validation` (bad directive)
- `unknown`

---

## 11) Reliability and offline behavior

### 11.1 Local durable queue (recommended)
The connector should store pending outbound signals locally when offline:
- sqlite db (recommended) or file-based queue
- include a dedupe key to avoid duplicates

### 11.2 Backoff and retry
- On FleetPrompt upload failure: exponential backoff with jitter.
- On Bridge failure: retry with backoff, surface a connector.error signal once connectivity resumes.

### 11.3 Ordering
Ordering is best-effort:
- Signals should include `occurred_at` so FleetPrompt can reason about time even if delivery is delayed.

---

## 12) FleetPrompt server-side requirements (supporting endpoints)

Phase 2D requires FleetPrompt to expose a minimal edge ingestion API.

### 12.1 Edge signals ingestion endpoint (cloud)
- `POST /api/edge/v1/signals`
  - Auth: Bearer token (connector API key)
  - Body: signal envelope
  - Behavior:
    - validate tenant from token
    - persist signal (tenant schema)
    - enforce dedupe (dedupe_key and/or source_event_id)
    - enqueue handlers
    - return 200 with signal id (or existing id on dedupe)

### 12.2 Edge directives polling endpoint (optional early)
- `GET /api/edge/v1/directives?connector_id=...&status=pending`
  - returns directives assigned to that connector
- `POST /api/edge/v1/directives/:id/ack`
- `POST /api/edge/v1/directives/:id/result`
  - (or reuse signals for directive status updates)

### 12.3 Security posture
- Never accept tenant selection from connector request parameters.
- Derive tenant from auth token.
- Apply rate limiting per connector and per tenant.

---

## 13) Package model: Proton Mail Edge Connector package (FleetPrompt marketplace)

This connector should be represented as a FleetPrompt package (metadata-only v1):
- `proton_mail_edge_connector`

Installation provisions:
- an Installation record
- required directives/signals handlers setup
- a “connector onboarding” page/flow (instructions, download, pairing)

### 13.1 Pairing flow (recommended UX)
1) User installs package in FleetPrompt Marketplace.
2) FleetPrompt shows a pairing code or connector API key issuance UI.
3) User configures edge connector with that key and Bridge host/ports.
4) Connector sends a `connector.heartbeat` signal.
5) FleetPrompt marks installation “connected” and ready.

---

## 14) Testing plan

### 14.1 Unit tests (connector)
- config validation
- dedupe key generation
- payload redaction rules
- offline queue behavior

### 14.2 Integration tests (connector + FleetPrompt)
- simulated IMAP inbox events produce `email.inbound.received` signals
- dedupe prevents duplicates on repeated polls
- directive polling returns directives; connector sends mail; emits outcome signals
- secrets never appear in signals/logs

### 14.3 Multi-tenancy tests (FleetPrompt)
- connector token for tenant A cannot write signals into tenant B
- dedupe constraints apply within tenant schema
- signals retention cleanup job does not cross tenants

---

## 15) Rollout plan

### Stage 1: Dev-only proof
- Use a local Proton Bridge + test Proton account.
- Ingest basic metadata signals and show them in FleetPrompt admin/debug UI.

### Stage 2: Design partner
- Add durable queue and robust retry behavior.
- Add basic outbound email sending directive (opt-in).

### Stage 3: Broader availability
- Add onboarding UX polish and support tooling:
  - last seen heartbeat
  - connector version mismatch warnings
  - replay instructions for support

---

## 16) Open questions (must be decided before implementation)

1) **Connector runtime target**
   - Elixir release? Go binary? Node?
   - (Recommendation: a static binary distribution is simplest for customers.)

2) **Directive delivery**
   - Poll-only in v1, or do we need a push/tunnel model?

3) **Email body handling policy**
   - Default remains metadata-only; do we allow body snippets? How long?
   - Do we support encrypted storage of bodies in FleetPrompt?

4) **Multi-account support**
   - One Proton account per connector profile in v1?
   - Multiple accounts later?

5) **Compliance and privacy defaults**
   - Do we hash email addresses in signals by default?
   - Or store them plainly for operability and rely on tenant isolation + access control?

---

## 17) Summary

Phase 2D makes Proton Mail a first-class part of FleetPrompt’s “communication triangle” by introducing an edge connector that:
- talks to Proton Mail Bridge over IMAP/SMTP,
- emits durable, deduplicated Signals into FleetPrompt,
- optionally receives Directives to send mail,
- stays secret-safe and tenant-safe,
- and remains operable under unreliable networks.

This is the correct architecture for Proton Mail in a SaaS platform because it respects Bridge’s local nature while preserving FleetPrompt’s core differentiators: package lifecycle, signals/directives, auditability, and reliable execution.