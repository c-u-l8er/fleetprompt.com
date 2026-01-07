# FleetPrompt — Phase 2C: Lighthouse Package Spec (Integration-First)
File: `fleetprompt.com/project_plan/phase_2c_lighthouse_package.md`  
Status: Spec (new)  
Last updated: 2026-01-06

## 0) Purpose (why Phase 2C exists)

Phase 2A makes packages *installable*.  
Phase 2B makes installs *real and operable* (Signals + Directives).

**Phase 2C proves the whole loop end-to-end** with one “lighthouse” package that:
- installs into a tenant via a Directive,
- provisions visible capability (workflow/agent template + config),
- executes reliably (Oban-backed),
- produces durable Signals + logs,
- delivers a user-visible outcome inside an external tool (integration-first).

This milestone is explicitly designed to solve the “marketplace chicken-and-egg” problem: we seed the ecosystem with one credible, demoable, retention-capable package.

---

## 1) Lighthouse package choice (v1)

### Package: Mattermost Daily Ops Digest
**Package slug:** `mattermost_daily_ops_digest`  
**Category:** `:operations` (horizontal, supports many verticals)  
**Primary surface:** Mattermost (outbound only in v1)  
**Primary value:** A daily (and on-demand) digest posted to a chosen Mattermost channel summarizing:
- recent package installs/upgrades/failures,
- executions completed/failed,
- top errors (by type),
- approximate cost/usage (if available),
- “recommended next action” (optional LLM summary).

This package is intentionally chosen as the first lighthouse because it:
- demonstrates the integration-first strategy without requiring multiple external data sources,
- uses FleetPrompt’s own Signals/Directives/Executions as the data source (so it works immediately),
- naturally exercises the platform primitives (signals retention, replay, directives auditability),
- can be extended later into vertical-specific reporting (marketing/ecom) by adding data source integrations as additional packages.

**Mattermost-specific rationale (why this is a strong first integration):**
- Many Mattermost deployments are self-hosted (strong privacy/compliance posture), which matches FleetPrompt’s integration-first + governance narrative.
- The easiest v1 delivery path is **Incoming Webhooks** (simple, reliable, low surface area).
- Mattermost also supports **Personal Access Tokens** for REST API access (useful later for richer capabilities).

---

## 2) Non-goals (explicitly out of scope for Phase 2C)

To keep the lighthouse package shippable and safe, v1 does **not** include:
- inbound Mattermost events (no Events API subscriptions in v1),
- interactive Mattermost buttons/actions or slash commands,
- multi-workspace Mattermost “connect many workspaces” support,
- posting to private channels,
- any third-party “package code execution” model (packages remain metadata + templates + platform-owned handlers),
- multi-source agency reporting (GA4/Ads/Shopify/etc. are future packages),
- marketplace third-party publishing.

---

## 3) Success criteria (exit criteria)

Phase 2C is complete when all of the following are true:

### Install → configure → run → output
- A tenant can install `mattermost_daily_ops_digest` from the marketplace UI.
- Installation is driven by a **Directive** (`package.install`) and emits full lifecycle **Signals**:
  - `package.install.requested`
  - `package.install.started`
  - `package.install.completed` OR `package.install.failed`
- The tenant can configure:
  - Mattermost connection (incoming webhook URL or personal access token)
  - target channel (optional if the incoming webhook is bound to a channel)
  - schedule time + timezone
  - optional: “include LLM summary” toggle
- The tenant can click “Run now” and receive a Mattermost message in the configured channel within ~30–60 seconds.

### Operability + safety
- All side effects are idempotent:
  - no duplicate Mattermost messages due to job retries (dedupe enforced)
  - no duplicate installs due to double-clicks (directive idempotency)
- No secrets appear in:
  - Signals
  - logs
  - execution outputs stored in DB (token material must never be persisted)
- The system can answer: “what happened?” for any install or run:
  - directive history + signals + execution logs

### Time-to-value
- Target: **< 15 minutes** from install to first digest posted.

---

## 4) Package contract (metadata-only v1)

This package definition must be representable in the `Package` registry (public schema) and must declare:

### Identity
- `slug`, `name`, `version`, `description`, `category`
- `publisher`: FleetPrompt (curated)

### Capabilities
- Provides:
  - 1 workflow template: `daily_ops_digest`
  - 1 agent template (optional): `digest_generator`
  - 1 integration binding: Mattermost credential (incoming webhook URL or PAT) + message posting action

### Consumes signals
- `package.*` lifecycle signals (install/upgrade/failed)
- `directive.*` lifecycle signals
- `agent.execution.*` signals (completed/failed)
- (optional) `workflow.run.*` signals

### Emits signals (minimum)
- `mattermost.digest.requested`
- `mattermost.digest.generated`
- `mattermost.message.posted`
- `mattermost.message.failed`

### Permissions / auth model (Mattermost)
Mattermost supports multiple integration authentication models. For v1, prefer the simplest, lowest-risk option:

**Option A (recommended v1): Incoming Webhook**
- You configure an incoming webhook in Mattermost that yields a URL like:
  - `https://your-mattermost-server.com/hooks/<generatedkey>`
- FleetPrompt posts JSON payloads to that URL to create messages.
- **Treat the webhook URL as a secret** (anyone with it can post).

**Option B (later): Personal Access Token (PAT)**
- PATs can authenticate FleetPrompt against the Mattermost REST API.
- PATs do not expire by default; treat them as high-sensitivity credentials.
- This unlocks richer features (channel discovery, richer posts, etc.) but increases scope and risk.

**V1 scope stance:**
- No OAuth scopes are required for Incoming Webhooks.
- For PAT-based integrations, keep the token permissions minimal (e.g., a dedicated bot/user with limited posting capability).

---

## 5) Data model impact (what gets created)

### Tenant-scoped resources (in `org_<slug>` schema)
This lighthouse package assumes Phase 2B primitives exist:

1) `signals` (Phase 2B)
2) `directives` (Phase 2B)

Additionally, this package requires:

3) `installations` (Phase 2A)
4) `integration_credentials` (recommended; tenant-scoped)
   - stores Mattermost credentials encrypted at rest (incoming webhook URL and/or personal access token)
   - stores Mattermost server identifiers/metadata (e.g., base URL, team/workspace identifiers if applicable)
   - stores granted roles/scopes/permissions metadata (as applicable) + status
5) `workflows` / `workflow_runs` (Phase 4-lite or a minimal subset)
6) `agent_executions` / `execution_logs` (Phase 4-lite)

If full workflow/agent resources aren’t implemented yet, Phase 2C may implement a minimal scheduled runner that directly creates `Execution` records.

### Optional tenant-scoped table (strongly recommended for dedupe)
7) `outbound_messages` (or reuse signals)
- tracks `(provider, tenant, destination, client_msg_id, status, posted_at)`
- allows strict idempotency for outbound posting

If you don’t add this table, you must enforce idempotency via `Signal.dedupe_key` and ensure the Mattermost post operation is protected by a stable dedupe key (so retries do not duplicate posts).

---

## 6) Configuration schema (installation config)

The installation configuration (tenant-owned) should include:

### Required
- `mattermost_credential_id` (uuid) — references encrypted credential record (incoming webhook URL or PAT)
- `timezone` (string) — IANA timezone name (e.g., `America/New_York`)
- `schedule_time` (string) — `HH:MM` (24h) local time
- `enabled` (boolean) — default true

### Optional (v1)
- `channel` (string | null) — Mattermost **public** channel name (e.g., `town-square`).
  - If the tenant uses an incoming webhook that is configured for a fixed channel in Mattermost, this can be omitted (FleetPrompt posts to the webhook’s default channel).
  - If provided, FleetPrompt may override the channel in the payload (when supported/allowed by the Mattermost server configuration).
- `include_llm_summary` (boolean) — default false initially (keeps costs bounded)
- `max_lines` (integer) — how long the digest can be
- `include_cost_estimates` (boolean) — if you have cost fields in executions
- `post_as_username` (string) — override username if Mattermost server allows it
- `post_icon_url` (string) — override icon if Mattermost server allows it

**Config validation rules**
- `timezone` must be valid IANA name
- `schedule_time` must parse
- `channel` may be empty/null; if present, it must be non-empty and conform to Mattermost naming rules (if you validate strictly)
- `enabled` can be toggled only by org admin roles

---

## 7) Installation flow (Directive-driven)

### Step-by-step (happy path)
1) User clicks **Install** on marketplace detail page.
2) Backend creates:
   - `Installation` (tenant-scoped) with status `requested/queued`
3) Backend creates:
   - `Directive` (`type = "package.install"`) with params:
     - `package_slug`, `version`, `installation_id`, `config` (initial empty)
     - `actor_user_id`, `actor_role`, `correlation_id`
   - `DirectiveRunner` job is enqueued.
4) Directive runner:
   - emits `package.install.started`
   - provisions tenant records:
     - workflow template record `daily_ops_digest` (or schedule record)
     - agent template record `digest_generator` (optional)
     - installation defaults
   - marks installation `installed`
   - emits `package.install.completed`

### Installation idempotency (required)
Use directive idempotency:
- `idempotency_key = "dir:pkg_install:{tenant}:{package_slug}:{version}:{config_checksum}"`

If the user double-clicks:
- return the existing directive + installation state, do not create duplicates.

---

## 8) Credential setup (Mattermost)

### UX stance (v1)
Credential setup is treated as part of “Configure after install”:
- After install completes, the UI shows:
  - “Connect Mattermost” (choose auth method)
  - “Set channel” (channel name)
  - “Test post” (Run now)

Recommended v1 UX: **Incoming Webhook**
- User pastes an incoming webhook URL created in Mattermost.
- FleetPrompt validates it by sending a minimal test post (or by doing a dry-run validation if you prefer).

Optional (later) UX: **Personal Access Token (PAT)**
- User supplies:
  - Mattermost base URL
  - PAT token
- FleetPrompt uses the REST API for richer functionality.

### Backend stance (security)
- Store Mattermost credentials encrypted at rest:
  - Incoming Webhook URL is a secret (it is effectively a bearer credential).
  - PAT token is a secret (high sensitivity).
- Never store credentials in Signals, logs, or execution results.
- Credential status transitions emit signals (optional):
  - `integration.credential.connected`
  - `integration.credential.revoked`

### Mattermost integration prerequisites (user-facing note)
- Incoming webhooks may be disabled on some Mattermost servers; a System Admin may need to enable them in the Mattermost System Console.
- Username/icon overrides may be disabled by server configuration; treat overrides as best-effort.

---

## 9) Execution model (how the digest is generated and posted)

### Two triggers (v1)
1) Scheduled run (daily at configured time)
2) Manual “Run now” action (UI button)

Both triggers must create a durable run record:
- either a `WorkflowRun` or an `Execution` with correlation ids.

### Execution steps (recommended)
1) Collect last 24 hours of tenant events:
   - signals by type:
     - `package.*`
     - `directive.*`
     - `agent.execution.*`
   - optionally group and count
2) Format digest message:
   - v1: deterministic formatting (no LLM required)
   - v1.1+: optional LLM summarization on top of the deterministic stats
3) Post message to Mattermost:
   - v1 (recommended): POST to the configured **Incoming Webhook URL** with a JSON payload (e.g., `text`, and optionally `channel`, `username`, `icon_url`)
   - later (optional): use the Mattermost REST API authenticated with a PAT
   - enforce idempotency so retries do not duplicate posts
4) Emit signals:
   - `mattermost.digest.generated`
   - `mattermost.message.posted` or `mattermost.message.failed`

### Correlation + causation
- Scheduled run correlation_id example:
  - `corr = "digest:{tenant}:{YYYY-MM-DD}:{channel_id}"`
- Manual run correlation_id example:
  - `corr = "digest:{tenant}:manual:{execution_id}"`

These correlation ids must propagate to:
- directive (if invoked by directive)
- execution record
- signals emitted
- logs

---

## 10) Idempotency + retry semantics (no duplicate Mattermost messages)

### Required behavior
If the job retries (network error, transient Mattermost issue), FleetPrompt must not post multiple messages.

### Recommended mechanism (pick one, but be explicit)
**Option A (preferred): Outbound message ledger**
- Before posting to Mattermost, upsert an `outbound_messages` record with:
  - `dedupe_key = "mattermost_post:{tenant}:{channel}:{digest_window}:{schedule_time}"`
- If record exists in `posted` status, no-op.
- If record exists as `posting`, ensure lock/atomic update prevents concurrent posts.

**Option B: Signal-enforced dedupe**
- Emit `mattermost.digest.generated` with a unique `dedupe_key`.
- Only post to Mattermost if the “post intent” signal insert succeeds (i.e., dedupe passes).
- Mark success/failure via additional signals.

Either way, the dedupe key should be stable for a given run window.

### Mattermost rate limiting
- Enforce a per-tenant limit:
  - manual “Run now” allowed at most N times per hour (e.g., 3/hr)
- Scheduled run is once per day; should always be allowed.

---

## 11) Failure modes + user-facing troubleshooting

### Expected failures
- Incoming webhook URL invalid/revoked (or PAT invalid/revoked)
- Mattermost channel not found / override channel rejected by server
- Mattermost API/webhook rate limits or transient errors
- Tenant has no signals yet (empty digest)

### Required UX surfaces
- Installation page must show:
  - current status and last error
  - “Reconnect Mattermost” if credential invalid
  - “Retry run” button (manual)
- Admin/support view must show:
  - last N signals related to this installation
  - last N executions/workflow runs and logs

### Required signals for failures
- `mattermost.message.failed` must include:
  - error kind classification (`auth`, `rate_limit`, `network`, `validation`, `unknown`)
  - safe error metadata (no tokens, no headers)

---

## 12) Observability requirements (minimum)

For every install and run:
- directive record exists (install)
- signals exist and are replayable (30-day retention)
- execution/workflow run logs exist (if Phase 4-lite is in place)

Emit telemetry events (optional but recommended):
- `fleetprompt.package.install.*`
- `fleetprompt.directive.*`
- `fleetprompt.mattermost.post.*`
- `fleetprompt.digest.run.*`

---

## 13) Security requirements (must pass before onboarding real tenants)

- Tokens encrypted at rest.
- No secrets in signals.
- No secrets in logs.
- Directive requests role-gated (org owner/admin).
- Web endpoints protected from CSRF (browser flows).
- OAuth callback validates state/nonce and binds to the correct tenant.

---

## 14) Testing plan (minimum)

### Unit tests
- Config validation (timezone, schedule_time, channel_id)
- Dedupe key stability (same inputs produce same key)
- Signal emission rejects non-JSON-safe payloads

### Integration tests
- Install flow emits expected signals and results in installation `installed`
- Manual run creates execution record and emits signals
- Mattermost post call is stubbed and:
  - success path emits `mattermost.message.posted`
  - failure path emits `mattermost.message.failed`
  - retries do not duplicate outbound message

### Multi-tenancy tests
- Credential record cannot be accessed across tenants
- Signals and directives are tenant-scoped and cannot leak

---

## 15) Rollout plan (how to ship safely)

### Stage 1: Internal only (dev/staging)
- Install + configure + run works end-to-end
- Ensure no secrets in signals/logs
- Validate dedupe under forced retries

### Stage 2: Design partners (small number)
- Add guardrails:
  - manual run rate limit
  - cost caps if LLM summary enabled
- Add a simple “health” status surface:
  - last successful post timestamp

### Stage 3: Public marketplace listing (curated)
- Add better onboarding UX:
  - connect Mattermost first if desired
  - channel selection UX (or “use webhook default channel” UX)
- Add “value event” tracking signals for GTM:
  - `value.digest.posted` with tenant + timestamp + destination (no message content)

---

## 16) Future expansion (intentionally not required for Phase 2C completion)

- Add inbound Mattermost triggers:
  - slash command or webhook-triggered “digest now”
  - interactive message actions (if/when you add richer integration)
- Add multiple digest templates:
  - “Ops digest” (platform health)
  - “Agency daily client digest” (requires analytics integrations)
- Add MCP compatibility layer:
  - expose digest generation tools as MCP “tools”
  - consume external MCP tools for data sources
- Add channel routing rules:
  - different digests per channel / team

### Proton Mail integration notes (replace Gmail strategy)
Proton Mail is privacy-first and attractive as an integration target, but it has a key architectural constraint for a SaaS platform:

- Proton Mail’s standard IMAP/SMTP access is typically provided via **Proton Mail Bridge**, which:
  - runs locally on the customer’s machine,
  - exposes IMAP/SMTP to mail clients,
  - is available only on **paid Proton plans** (per Proton documentation).

**Implication for FleetPrompt:**
- A pure “cloud-only” Proton Mail integration is not straightforward using standard IMAP/SMTP, because the Bridge is a local component.
- The most realistic path is an **edge connector** model:
  - a customer-controlled FleetPrompt runner connects to Proton Mail via Proton Mail Bridge locally,
  - the runner forwards normalized events into FleetPrompt as Signals (webhook → signal),
  - outbound mail can be sent via the same runner using SMTP through Bridge (or via Proton Business SMTP if available for the tenant).

**Actionable v1 stance:**
- Keep Phase 2C focused on Mattermost as the lighthouse.
- Track Proton Mail integration as a follow-on package that is either:
  - “Proton Mail (Bridge-based) Connector” (edge-runner required), or
  - “Proton Business SMTP Sender” (outbound only) if the customer has a business plan that supports SMTP for business applications.

In both cases:
- credentials must be encrypted at rest,
- never store message bodies or secrets in Signals by default,
- use idempotency keys based on provider message ids (or stable hashes) to avoid duplicate ingestion.

---

## 17) Summary

Phase 2C ships one integration-first package that proves FleetPrompt’s core thesis:
- packages install into tenants,
- directives make changes auditable,
- signals make operations replayable,
- executions make outcomes measurable,
- and customers see value inside an existing tool (Mattermost).

This lighthouse package becomes the demo asset, the reference implementation for future packages, and the first anchor of marketplace credibility.