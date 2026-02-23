# FleetPrompt — Phase 2B: Persisted Signals + Directives (Platform Primitives)

Status: Spec (new)
Last updated: 2026-01-06

## Why Phase 2B exists

Phase 2A (Marketplace + Installations) makes packages *discoverable* and *installable* as records.

Phase 2B makes packages **real** and **operable** by introducing two platform primitives:

1) **Signals** — persisted, replayable events that represent “what happened” in a tenant.
2) **Directives** — persisted, auditable commands that represent “what we intend to change” in a tenant.

Together, these primitives turn FleetPrompt from “CRUD + jobs” into a durable automation platform:
- installs are observable and replayable,
- upgrades are controlled and auditable,
- integrations and workflows can be composed as signal chains,
- future connectors/webhooks become “signal sources,” not bespoke feature code.

This phase is intentionally scoped to work with FleetPrompt’s current stack:
- Phoenix controllers for HTTP edges
- Ash resources/domains for modeling + tenancy
- Oban for durable async execution
- PubSub for realtime UX (optional) layered on top of persistence

---

## Prerequisites

- Phase 1: multi-tenant foundation (organizations, memberships, tenant selection) is complete.
- Phase 2A: `Package` (global) and `Installation` (tenant-scoped) exist (or are being implemented).
- Oban is present and working (it is).

## Related requirements (canonical docs)
Phase 2B is tightly coupled to two cross-cutting requirements. Treat these as part of the acceptance criteria for Signals/Directives:

- Security + credential handling (no secrets in signals; encrypt credentials at rest; role gating):
  - `fleetprompt.com/project_theory/SECURITY_AND_CREDENTIALS.md`
- Tenancy operations + migration tooling (schema-per-tenant scaling guardrails; migration status tracking; throttled fanout):
  - `fleetprompt.com/project_theory/TENANCY_SCALING_PLAN.md`

---

## Phase 2B goals (exit criteria)

### Signals (persisted events)
- A tenant-scoped `Signal` resource exists and is persisted to `org_<slug>.signals`.
- Signals include correlation and causation identifiers and can be replayed.
- The platform has a single “emit” entrypoint that:
  - validates and persists the signal,
  - publishes a PubSub notification (optional),
  - enqueues handler jobs (durable fanout).

### Directives (persisted commands)
- A tenant-scoped `Directive` resource exists and is persisted to `org_<slug>.directives`.
- Directives are role-gated (org-admin by default) and idempotent.
- A `DirectiveRunner` job executes directives and emits signals for lifecycle:
  - `directive.requested`
  - `directive.started`
  - `directive.completed` / `directive.failed`

### Operational proof
- Installing a package uses a directive and emits a full signal trail:
  - `package.install.requested`
  - `package.install.started`
  - `package.install.completed` (or failed)
- A replay function can re-process signals for debugging in a tenant.

---

## Architectural stance

### Signals are immutable facts
A signal is an immutable record of a thing that happened:
- “package install started”
- “slack message received”
- “agent execution completed”
- “workflow step failed”

Signals are not edited. If something changes, that produces new signals.

### Directives are controlled intent
A directive is a request to make a change:
- “install package X@1.2.0”
- “upgrade package X from 1.2.0 → 1.3.0”
- “enable integration credentials”
- “disable package”

Directives are:
- persisted,
- auditable,
- run asynchronously,
- safe to retry,
- idempotent.

### Relationship between them
- A directive execution emits signals as it progresses.
- Signals can trigger follow-on directives (later phases), but Phase 2B keeps this minimal.

---

## Package execution model stance (Phase 2B)
This spec assumes **packages are metadata-only in v1**.

### What “metadata-only” means
- Packages do **not** ship arbitrary executable code that runs inside FleetPrompt at install time or runtime.
- A package can provision:
  - tenant records (installations, agents, workflows, skills references/templates),
  - configuration schemas and defaults,
  - integration bindings (credential references, webhook registrations handled by platform code),
  - signal handlers that map to **platform-owned** handler modules.
- The actual execution logic (jobs, handlers, tool calls) remains **first-party platform code** so we can guarantee:
  - tenant isolation,
  - auditability and replay semantics,
  - security boundaries,
  - predictable upgrades.

### Why this matters
Allowing third-party code execution introduces immediate requirements that Phase 2B intentionally avoids:
- sandboxing/isolation model (containers/VMs/BEAM library loading constraints),
- code signing and publisher verification,
- permission model for filesystem/network/tool access,
- incident response and rollback story for malicious or broken releases.

### Future path (explicitly out of scope for Phase 2B)
If you later decide to allow executable packages, treat it as a dedicated phase with:
- signed package artifacts,
- a constrained runtime sandbox,
- explicit capability permissions,
- deterministic upgrade and rollback semantics.

---

## Data model (tenant schema)

These tables live in each tenant schema (`org_<slug>`). This keeps event data isolated and simplifies retention policies per org.

### Table: `signals`
Core fields (recommended):
- `id` (uuid PK)
- `type` (string) — stable event name like `package.install.completed`
- `source` (string) — `marketplace`, `webhook:slack`, `job:directive_runner`, etc.
- `subject_type` (string, nullable) — e.g. `package_installation`, `agent`, `workflow_run`
- `subject_id` (uuid, nullable)
- `data` (map/jsonb) — event payload, must be JSON-safe
- `metadata` (map/jsonb) — trace/correlation, actor info, schema version, etc.
- `occurred_at` (utc_datetime_usec) — when the event actually occurred
- `inserted_at` / `updated_at`

Idempotency / de-duplication fields:
- `dedupe_key` (string, nullable) — deterministic key to prevent duplicate ingestion
- `source_event_id` (string, nullable) — provider event id (Slack event id, webhook id, etc.)

### Concrete dedupe key schemes (recommended)
These schemes make replay, retries, and webhook ingestion safe without creating duplicate facts.

#### 1) Package install lifecycle signals
Use a stable key derived from tenant + package + version (+ config checksum if relevant):

- `package.install.requested`:
  - `dedupe_key = "pkg_install_req:{tenant}:{package_slug}:{version}:{config_checksum}"`
- `package.install.started`:
  - `dedupe_key = "pkg_install_start:{tenant}:{installation_id}"`
- `package.install.completed`:
  - `dedupe_key = "pkg_install_done:{tenant}:{installation_id}:{installed_version}"`
- `package.install.failed`:
  - `dedupe_key = "pkg_install_fail:{tenant}:{installation_id}:{attempt}"`

Notes:
- `config_checksum` should be a stable hash of normalized config (sorted keys, no secrets, no timestamps).
- Prefer `installation_id` once it exists; it is the cleanest stable subject for downstream joins.

#### 2) External webhook ingestion signals
Prefer provider event ids where available:

- `source = "webhook:slack"`
- `source_event_id = "{slack_event_id}"`
- Unique constraint on `(source, source_event_id)` prevents duplicates across retries.

If a provider does not supply a stable event id, construct a `dedupe_key` from:
- provider name,
- tenant integration instance id,
- canonicalized payload hash,
- occurred_at bucket (only if necessary).

#### 3) Internal job emission signals
If a job might emit the same signal multiple times due to retries, set:
- `dedupe_key = "job:{job_id}:{signal_type}"`

This prevents “double emit” facts during Oban retries.

Indexes/constraints:
- index on `type`
- index on `occurred_at`
- index on `(subject_type, subject_id)`
- unique index on `(source, source_event_id)` where `source_event_id` is not null
- unique index on `dedupe_key` where `dedupe_key` is not null

### Table: `directives`
Core fields (recommended):
- `id` (uuid PK)
- `type` (string) — stable directive name like `package.install`
- `status` (string/enum) — `requested | running | completed | failed | cancelled`
- `params` (map/jsonb) — command input (validated by type)
- `result` (map/jsonb, nullable) — outputs (ids created, versions applied, etc.)
- `error_kind` (string, nullable)
- `error_message` (string, nullable)
- `error_details` (map/jsonb, default `{}`)
- `requested_at` (utc_datetime_usec)
- `started_at` (utc_datetime_usec, nullable)
- `completed_at` (utc_datetime_usec, nullable)
- `actor_user_id` (uuid, nullable) — references public-schema `users.id` logically
- `actor_role` (string, nullable) — snapshot for audit
- `correlation_id` (string, nullable)
- `causation_id` (string, nullable)
- `idempotency_key` (string, nullable) — stable command dedupe key (see below)
- `inserted_at` / `updated_at`

### Concrete directive idempotency key schemes (recommended)
Directives represent intent. Retrying a request (or double-clicking in UI) must not create duplicate changes.

#### `package.install`
- `idempotency_key = "dir:pkg_install:{tenant}:{package_slug}:{version}:{config_checksum}"`
- If the same `idempotency_key` is requested again:
  - return the existing directive (and its current status)
  - do not create a new directive

Behavior on mismatch:
- If the key collides but params differ (should only happen if checksum is wrong), treat as an error and surface it as a failed directive request (do not “guess”).

#### `package.enable` / `package.disable` (if implemented)
- `idempotency_key = "dir:pkg_toggle:{tenant}:{installation_id}:{target_state}"`

#### Retry semantics
- The `DirectiveRunner` job must be safe to run multiple times:
  - if status is already `completed`/`failed`, no-op
  - if status is `running`, avoid redoing side effects unless your underlying installer is also idempotent

Indexes/constraints:
- index on `type`
- index on `status`
- unique index on `idempotency_key` where not null

---

## Naming conventions (non-negotiable)

### Signal names
Use dot-delimited lowercase “domains”:

- `package.install.requested`
- `package.install.started`
- `package.install.completed`
- `package.install.failed`
- `package.upgrade.requested`
- `directive.requested`
- `directive.started`
- `directive.completed`
- `directive.failed`

Avoid embedding versions in event names. Put versions in `data`.

### Directive names
Use dot-delimited “commands”:

- `package.install`
- `package.upgrade`
- `package.enable`
- `package.disable`
- `package.uninstall`

---

## Signal envelope (canonical payload)

Every signal must be representable as this envelope at runtime, even if it is persisted as columns + `data/metadata`.

Recommended canonical struct shape:

- `id` (uuid)
- `type` (string)
- `occurred_at` (datetime)
- `source` (string)
- `tenant` (string) — `org_demo` schema name, kept in runtime context (not required as a DB column)
- `subject`:
  - `type` (string | nil)
  - `id` (uuid | nil)
- `data` (map)
- `metadata` (map):
  - `schema_version` (integer, starts at 1)
  - `correlation_id` (string | nil)
  - `causation_id` (string | nil)
  - `trace_id` / `span_id` (optional)
  - `actor_user_id` (uuid | nil)
  - `actor_role` (string | nil)

---

## Implementation plan (backend)

### Step 1 — Add a Signals domain
Create a new Ash domain:
- `FleetPrompt.Signals`

Add it to `:ash_domains` configuration.

### Step 2 — Create `FleetPrompt.Signals.Signal` resource (tenant-scoped)
- Data layer: `AshPostgres.DataLayer`
- Table: `signals`
- `multitenancy :context`

Actions:
- `create :emit`
  - accept: `type, source, subject_type, subject_id, data, metadata, occurred_at, dedupe_key, source_event_id`
  - validate presence: `type`, `source`
  - default `occurred_at` to now if missing
  - enforce JSON-safe `data` and `metadata` (no structs, no pids)
- `read :recent`
  - argument: `limit`, `type`, `subject_id`, etc.
- `read :by_id` (default read)
- `destroy` should be disallowed for normal users; retention should be handled by explicit admin operations or background cleanup jobs.

Database considerations:
- Use jsonb for `data` and `metadata`.
- Create unique indexes for idempotency keys.

### Step 3 — Add a SignalBus module (single entrypoint)
Introduce a single module as “the way to emit a signal”:

Responsibilities:
1) Validate + persist the signal in the tenant schema via Ash.
2) Publish a PubSub notification (optional) for realtime UI.
3) Enqueue handler job(s) for durable processing.

Minimum interface (conceptual):
- `emit(type, opts)` where opts includes:
  - `tenant`
  - `source`
  - `subject`
  - `data`
  - `metadata`
  - optional `dedupe_key` / `source_event_id`

Important: `emit/2` must be safe to call from jobs and controllers and should return:
- `{:ok, signal}` if inserted (or already exists via idempotency)
- `{:error, reason}` otherwise

Idempotency behavior:
- If `dedupe_key` or `(source, source_event_id)` collide, treat as:
  - return existing signal (preferred)
  - do not re-enqueue handlers unless explicitly requested

### Step 4 — Create a minimal handler fanout mechanism (durable)
For Phase 2B MVP, choose a simple approach:

- Maintain a registry mapping `signal.type` to handler modules.
- For each handler, enqueue an Oban job `SignalHandlerJob` with:
  - `signal_id`
  - `tenant`
  - `handler_module` (string)

Handler contract:
- `handle_signal(signal, context) :: :ok | {:error, term}`

Do not run handlers inline in HTTP requests. Always enqueue for durability, unless explicitly a “sync handler” for local UI.

### Step 5 — Create a Signal Replay module
Add a replay utility:
- `replay_signal(signal_id, tenant, opts)`
- `replay_tenant(tenant, filters, opts)`

Replay should:
- load signals from DB,
- re-enqueue handler jobs,
- optionally bypass idempotency for handler side effects (default should be safe).

Replay is a debugging tool and must be admin-only.

---

## Implementation plan (directives)

### Step 6 — Add a Directives domain
Create new Ash domain:
- `FleetPrompt.Directives`

Add it to `:ash_domains`.

### Step 7 — Create `FleetPrompt.Directives.Directive` resource (tenant-scoped)
- Data layer: `AshPostgres.DataLayer`
- Table: `directives`
- `multitenancy :context`
- Extension: `AshStateMachine` (recommended)

States:
- `requested` (initial)
- `running`
- `completed`
- `failed`
- `cancelled` (optional for Phase 2B; implement if useful)

Actions:
- `create :request`
  - accept: `type, params, actor_user_id, actor_role, correlation_id, causation_id, idempotency_key`
  - validate directive type is allowed
  - validate params by directive type (see below)
  - enforce authorization (org admin by default)
- state transition actions:
  - `start`
  - `complete`
  - `fail`
  - `cancel`

Authorization:
- Directives are privileged operations.
- Policy baseline: only org admins can request directives (owner/admin roles).
- Jobs can mutate directive status when running (system context).

Idempotency:
- Enforce uniqueness on `idempotency_key` where present.
- If a directive request collides, return the existing directive.

### Step 8 — Directive type system (v1)
Implement a directive router/executor:

Supported directive types in Phase 2B:
1) `package.install`
   - params:
     - `package_slug` (string)
     - `version` (string | "latest")
     - `installation_id` (uuid | optional if Phase 2A creates it first)
     - `config` (map, optional)
2) `package.upgrade` (optional in 2B; can be 2C)
3) `package.enable` / `package.disable` (optional in 2B)
4) `package.uninstall` (optional in 2B)

For Phase 2B MVP, you must implement at least `package.install`.

### Step 9 — Create `DirectiveRunner` Oban job
Add an Oban worker:
- inputs:
  - `directive_id`
  - `tenant`

Responsibilities:
1) Load the directive in tenant context.
2) Emit `directive.started` signal.
3) Execute the directive by type:
   - for `package.install`:
     - ensure installation exists or create it
     - call the Phase 2A installer logic (job or service)
4) Persist results to directive.
5) Emit `directive.completed` or `directive.failed` signal.

Important:
- Directive runner must be idempotent.
- If a directive is already completed/failed, the job should no-op.

---

## How Phase 2A should integrate with Phase 2B (required realignment)

Phase 2A “install package” UI flow should become:

1) User clicks Install
2) Backend creates a tenant-scoped `Installation` row in `queued/requested`
3) Backend creates a tenant-scoped `Directive` (`package.install`) with:
   - `installation_id`
   - `package_slug`, `version`
   - actor + correlation ids
4) Backend enqueues `DirectiveRunner`

The Phase 2A `PackageInstaller` job can remain as an internal detail, but it should be driven by the directive runner, and both should emit signals.

Minimum signal trail for install:
- `package.install.requested` (when directive requested)
- `directive.requested`
- `directive.started`
- `package.install.started`
- `package.install.completed` OR `package.install.failed`
- `directive.completed` OR `directive.failed`

---

## Middleware (Phase 2B “lite”)

Full signal middleware stacks can be built later, but Phase 2B should include at least:

1) **Tenant enforcement**
   - never emit signals without an explicit tenant
2) **Redaction guard**
   - prevent secrets/tokens from being stored in `data/metadata`
3) **Normalization**
   - ensure event payloads are JSON-encodable
4) **Correlation defaults**
   - if missing correlation_id, generate one at directive/request boundaries

---

## Observability requirements (Phase 2B)

Every directive execution must write:
- signals (as above)
- structured log lines including:
  - tenant
  - directive_id
  - package_slug/version (if applicable)
  - correlation_id / causation_id

Additionally, emit telemetry events (optional in Phase 2B but recommended):
- `[:fleetprompt, :signal, :emitted]`
- `[:fleetprompt, :directive, :requested]`
- `[:fleetprompt, :directive, :completed]`
- `[:fleetprompt, :directive, :failed]`

These can later power dashboards and alerting.

---

## Security and policies (must be explicit)

### Who can request directives?
Baseline:
- Only members with role `owner` or `admin`.

### Who can read signals?
- Org members can read signals in their tenant (at least via admin/operator UI).
- If signals include sensitive content, add signal-level classification:
  - `visibility: internal|admin_only`
  - enforce via policies.

### Never store secrets in signals
Signals are durable and replayable. Treat them as logs. Never store:
- OAuth access tokens
- refresh tokens
- raw API keys
- passwords

Store references (credential ids) instead.

---

## Retention policy (Phase 2B default)

Signals can grow quickly. For Phase 2B, default to a single global retention rule:

- Default retention: 30 days for all signals (no per-type exceptions in v1)

Cleanup approach (recommended):
- nightly Oban job per tenant to delete signals with `occurred_at` older than 30 days
- job must run in the tenant context and should be idempotent (safe to retry)
- consider batching deletes to avoid long locks (implementation detail)

---

## Verification checklist

### Local functional checks
- [ ] Creating a directive persists a directive record in the tenant schema.
- [ ] Enqueued directive runner moves directive through states.
- [ ] Signal emission persists signals in tenant schema for each lifecycle step.
- [ ] Dedupe behavior works for `dedupe_key` and `(source, source_event_id)` collisions.
- [ ] Replay can re-enqueue handler jobs without corrupting state.

### Operational checks
- [ ] Logs include tenant and correlation ids for directive runs.
- [ ] Failure paths produce `*.failed` signals and preserve error_kind/message/details.
- [ ] Directive runner is safe to retry.

---

## Testing strategy (minimum for Phase 2B)

1) Unit tests: Signal persistence
- emits a signal and can read it back
- rejects non-JSON-encodable payloads
- enforces dedupe uniqueness

2) Unit tests: Directive request validation
- invalid directive type rejected
- missing required params rejected
- idempotency key returns existing directive

3) Integration test: Package install directive emits lifecycle signals
- request directive
- run job (synchronously in test)
- assert signals exist in correct order/types
- assert installation state transitions (if Phase 2A is integrated)

---

## Next phase hooks (what this enables)

Once Signals + Directives exist:
- Phase 3 chat can become a “directive generator” (typed actions) rather than ad-hoc side effects.
- Integrations can normalize inbound events into signals with replay and audit.
- Workflow engine (Phase 4) can become a signal consumer/producer.
- API/Webhooks (Phase 5) can map external events to signals and signal outcomes to outbound webhooks.

---

## Summary

Phase 2B turns FleetPrompt’s marketplace from “install buttons” into a real platform with:
- durable, replayable events (signals),
- auditable state changes (directives),
- idempotent async execution via Oban,
- and a foundation for integrations and workflows that composes cleanly across tenants.