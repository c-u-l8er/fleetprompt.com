# FleetPrompt Architecture Theory (Aligned to Current Stack)

Last updated: 2026-01-06

This document is the architectural “theory of the product” for FleetPrompt: the core principles, boundaries, data model stance, and the execution/integration model that should guide implementation decisions as the codebase grows.

It is intentionally aligned to what is *already true* in the repo today:

- **Backend:** Phoenix (controllers), **Ash** (resources/domains), **AshPostgres** (schema-based multi-tenancy), **Oban** (jobs)
- **Frontend:** **Svelte + Vite** served as static assets by Phoenix
- **App delivery:** **Inertia** (server-driven SPA payloads)
- **Deployment:** Fly.io (single Phoenix app serving frontend assets)

It also incorporates the research direction (integration-first + package marketplace + agent execution), while acknowledging what’s implemented versus planned.

---

## 1) What FleetPrompt *is* (system identity)

FleetPrompt is an **AI integration layer** and **package marketplace** that lets an organization:

1) install “packages” (prebuilt integrations/agent capabilities),
2) configure and deploy agents,
3) execute work (manually via UI/chat/API or automatically via triggers),
4) observe results, cost, and reliability,
5) iteratively evolve their automation safely.

### Integration-first (strategic constraint)
FleetPrompt should assume customers already live in tools like email (including Proton Mail), Mattermost (and other team chat), CRMs, commerce, accounting, analytics, etc. The product wins by embedding AI into existing workflows, minimizing migration friction and behavior change.

**Architecture implication:** the system must treat integrations as first-class runtime concerns (credentials, webhooks, rate limits, retries, idempotency, audit logs, and tenant isolation).

### First-party applications (clients), not just integrations
FleetPrompt should explicitly support multiple **first-party product surfaces** that all speak the same internal “language” (signals + directives + executions):

1) **Operator Console** (current: Inertia + Svelte)
   - install/configure packages, inspect executions/logs, run workflows, manage credentials.

2) **Agent-native Forum** (proposed first-party app)
   - a discussion platform where **AI agents are first-class participants**:
     - humans can @mention agents,
     - agents can respond, summarize, route/escalate, and assist moderation,
     - every agent action is attributable and auditable.

**Key stance:** a first-party forum is a *client* of FleetPrompt’s primitives, not a separate engine. If the forum can’t be built mostly by emitting signals and running directives/executions, it is a sign the core primitives are incomplete.

---

## 2) Architectural principles (non-negotiables)

### P0 — Tenant isolation is a core invariant
- Every request operates in a **current organization context** (tenant).
- Tenant-scoped data must never leak across tenants.
- Schema-per-tenant is the chosen isolation model; keep it consistent.

### P1 — Resource-first domain modeling
Ash resources are the source of truth for:
- data shape,
- actions,
- validations,
- policies,
- relationships,
- multi-tenancy behavior.

Phoenix controllers are orchestration and I/O only.

### P2 — Async by default for anything non-trivial
Anything that can take time or fail due to network variability belongs in:
- **Oban jobs** (with retries, backoff),
- explicit state machines for traceability,
- idempotent semantics.

### P3 — “Packages” are the product surface area
Packages are not “code execution inside FleetPrompt” as a first step. In v1, packages are:
- registry metadata + configuration schema,
- installation lifecycle,
- runtime bindings to integrations, agents, workflows, skills, and signals.

**Package execution stance (v1):**
- Packages do **not** ship arbitrary executable code into the FleetPrompt runtime.
- Package behavior is expressed through **configuration + templates + directives** that activate **platform-owned** capabilities (integrations, skills, workflows, executors).
- If/when third-party code execution is introduced, it must come with explicit sandboxing, signing/verification, and a permission model (future phase; not assumed by the current plan).

If a feature doesn’t map to a package story, it is likely not core.

### P4 — The UI is a thin client over clear server contracts
With Inertia:
- the server owns routing and page props,
- the frontend owns interaction and presentation.

Avoid duplicating business logic in Svelte.

### P5 — Observability is part of correctness
If we can’t answer “what happened, for which org, why, and what did it cost?”, the system is incomplete.

---

## 3) System boundaries & major components

### 3.1 High-level component map

```
┌───────────────────────────────────────────────────────────────────┐
│                           Clients (Browser)                        │
│   - Operator Console (Svelte + Inertia)                             │
│   - Agent-native Forum (Svelte + Inertia; optional LiveView later)  │
└───────────────▲───────────────────────────────┬───────────────────┘
                │ Inertia HTML + JSON props      │ SSE/streaming
                │                               │ (Phase 3+)
┌───────────────┴───────────────────────────────▼───────────────────┐
│                      Phoenix Web Layer (HTTP)                      │
│ Controllers + Plugs: auth, org selection, tenant context,          │
│ inertia props, API router (future), webhooks (future)              │
└───────────────▲───────────────────────────────┬───────────────────┘
                │ Ash actions/queries            │ Enqueue jobs
┌───────────────┴───────────────────────────────▼───────────────────┐
│                         Ash Domains/Resources                       │
│ Accounts (public schema)                                            │
│ Tenant ops + primitives (tenant): Signals, Directives, Executions   │
│ Product domains (tenant): Agents, Workflows, Chat, Forum            │
│ Registry (public): Packages (+ global catalogs as needed)           │
└───────────────▲───────────────────────────────┬───────────────────┘
                │ SQL (schema-aware)             │ Job execution
┌───────────────┴───────────────────────────────▼───────────────────┐
│                      Postgres + Oban (runtime)                      │
│ public schema: orgs/users/memberships/packages/...                  │
│ org_<slug> schemas: signals/directives/agents/executions/...        │
│ oban tables in public                                               │
└───────────────────────────────────────────────────────────────────┘
```

**Important:** the forum is not “a separate system.” It is an additional first-party surface that produces and consumes the same tenant-scoped primitives (signals/directives/executions) as every other FleetPrompt workflow.

### 3.2 “Public vs tenant schema” theory
- **Public schema** stores *identity and platform-wide registry* data:
  - users
  - organizations
  - org memberships
  - global skills (if truly global)
  - package registry (global)
  - api keys (future)
  - billing (future)
- **Tenant schemas (`org_<slug>`)** store *org-owned operational data*:
  - agents and their configuration/state
  - executions + logs + metrics
  - workflows + runs
  - chat messages/conversations
  - **signals + directives** (persisted operational facts + auditable intent)
  - integration credentials/installs (depending on sensitivity and access patterns)

**Decision heuristic:** if data is meaningful only within one org’s operational boundary, it belongs in tenant schema.

---

## 4) Multi-tenancy model (theory aligned to current implementation)

### 4.1 Tenant selection is a user-level session concern
The system already implements:
- session auth,
- org membership,
- org selection to set current tenant context.

That should remain the single source of tenant context in the browser UI.

### 4.2 Tenant context propagation rules
- Every Ash call that touches tenant data must include `tenant` in context (or equivalent).
- Controllers should derive tenant from the org selection plug, not from user-submitted params.
- Admin tooling must constrain tenant selection to authorized orgs.

### 4.3 Schema lifecycle & resilience
Because schema-per-tenant involves DDL:
- org creation is a multi-step operation (create org row + create schema + tenant migrations).
- failures must be handled with cleanup / idempotency (detect orphan schemas, etc.).
- migrations must be safe across all tenants.

**Theory:** tenant schema operations are “infrastructure-like” and must be treated as transactional workflows with compensation.

### 4.4 Tenancy scaling plan (schema-per-tenant now, planned escape hatches later)
Schema-per-tenant is the correct choice for FleetPrompt’s current stage (isolation + trust), but it needs explicit “what happens at scale” planning:

- **Now (0–100s of tenants):** stay schema-per-tenant, but build migration tooling and status visibility early (batching, per-tenant status tracking, safe retries).
- **Later (100–500+ tenants):** introduce operational guardrails:
  - classify tenants (free/standard/premium) for migration and maintenance scheduling
  - batch and throttle tenant migrations
  - tighten connection pooling and background job concurrency to avoid DB pressure
- **Future (1000+ tenants / high volume):** plan for a tiered model:
  - keep schema-per-tenant for enterprise/compliance tiers
  - consider shared-schema (row-level isolation) for high-volume SMB tiers, or shard tenants across multiple databases

This is not a near-term rewrite requirement, but it is a near-term **tooling** requirement to prevent migrations and maintenance from becoming a blocker.

---

## 5) Core product primitives (FleetPrompt’s “language”)

These are the primitives FleetPrompt should standardize around. They map to research patterns while staying compatible with Ash + Oban.

### 5.1 Organization
Identity + plan + limits; owns tenant schema.

### 5.2 Package (global registry)
A package is a **versioned definition** of:
- capabilities (what it can do),
- configuration schema,
- dependencies (other packages, skills, integrations),
- required permissions/scopes (e.g., Mattermost incoming webhook access or personal access token roles; Proton Mail Bridge/SMTP constraints),
- install hooks (jobs/workflows to run),
- operational SLAs (rate limits, quotas).

A package is not “just UI.” It is something the system can install/uninstall and reason about.

### 5.3 Installation (tenant-owned lifecycle)
An installation is:
- package + version + tenant,
- configuration and credentials binding,
- status/state machine (installed, installing, failed, disabled),
- audit trail and error report.

### 5.4 Skill (capability unit)
A skill is a reusable capability that can be:
- referenced by agents/workflows,
- invoked directly in execution,
- tested independently.

Whether skills are global or tenant-owned should be explicit. If “global skill catalog” is intended, keep them global but allow tenant overrides via installation/config.

### 5.5 Agent (tenant-owned)
An agent is:
- a configured runtime entity with a purpose,
- references to skills/packages,
- execution policies (model, limits, tool permissions),
- lifecycle state machine.

### 5.6 Execution (tenant-owned)
An execution is a durable record of work:
- input, output, error,
- token usage and cost,
- tool calls,
- latency and performance,
- logs and trace context.

Executions are the key to observability and billing.

### 5.7 Workflow (tenant-owned)
Workflow orchestrates multiple steps:
- agent steps,
- conditional steps,
- parallel steps,
- integration actions,
- compensation/rollback (where appropriate).

### 5.8 Signals / Events (first-class, persisted, replayable)
FleetPrompt’s plan now treats signals as a **first-class persisted primitive** (tenant-scoped), not as “telemetry-only until later.”

**Persisted signals decision (current):**
- Signals are stored in a tenant schema table (e.g., `org_<slug>.signals`) and are designed to be:
  - immutable,
  - deduplicated (idempotency),
  - replayable for debugging/support,
  - attributable (correlation/causation + actor metadata).

**Pragmatic implementation (fits our stack):**
- Use Ash resources for `Signal` + `Directive`.
- Use Oban for durable handler fanout and directive execution.
- Use telemetry and structured logs as *additional* outputs, not substitutes for persistence.

**Why this matters:**
- Marketplace installs become “real” only when we can answer: what happened, who initiated it, what changed, and how to retry safely.
- Integrations (including emerging standards like MCP-style tool connectivity) still need a durable internal event record for auditability, replay, and long-running orchestration.
- A first-party **agent-native forum** becomes feasible (and safe) only if forum actions are representable as signals + directives with clear attribution and replay safety.

#### Actor model (required for agent-native participation)
Signals (and the directives/executions they trigger) must carry a consistent notion of “who did this”:

- `human` — a signed-in user (org member)
- `agent` — a tenant-owned agent identity (configured and permissioned)
- `system` — internal platform actor (jobs, schedulers, maintenance)
- `integration` — external system actor (webhooks, edge connector, provider events)

**Non-negotiables**
- Agents are not “anonymous automation.” If an agent posts, flags, summarizes, or routes, the UI must show:
  - agent identity (stable id + display name),
  - confidence/reasoning summary (as appropriate),
  - provenance link(s): related `execution_id` / `directive_id` / `signal_id`.
- High-risk side effects remain directive-gated and policy-checked:
  - e.g., “hide post”, “ban user”, “send email”, “post to Mattermost” should be a `Directive` (auditable, retry-safe), not an implicit model action.
- “Human override” is a feature:
  - humans must be able to correct/annotate agent output, and that feedback should be capturable as a signal.

#### Forum as a first-party signal surface (proposed)
A forum is a high-signal environment for agents because it produces dense, durable events (threads, replies, reactions, flags). Treat forum activity as a canonical event stream, not special-cased logic.

**Recommended forum signal taxonomy (v1)**
- `forum.thread.created`
- `forum.thread.viewed`
- `forum.post.created`
- `forum.post.edited`
- `forum.post.reacted`
- `forum.post.flagged`
- `forum.thread.solved`
- `forum.thread.locked`

**Agent interaction signals (v1)**
- `forum.agent.mentioned`
- `forum.agent.responded`
- `forum.agent.escalated` (agent chose to defer to humans)
- `forum.agent.summary.generated`
- `forum.agent.feedback.recorded` (helpful/not helpful, corrections)

**Directive examples (v1)**
- `forum.post.create` (agent response, summary, moderation note)
- `forum.post.flag` / `forum.post.hide` (if/when moderation automation is allowed)
- `forum.thread.summarize`
- `forum.thread.notify_experts` (routing/escalation)
- `forum.user.warn` / `forum.user.suspend` (only with strict policy + approval gating)

**Core stance:** the forum is where FleetPrompt can *prove* the primitives:
- inbound forum actions → signals,
- signals trigger executions/workflows,
- executions propose or perform work via directives,
- resulting forum changes are auditable, replayable, and attributable.

---

## 6) Execution & streaming theory (how work happens)

### 6.1 The “work pipeline”
For anything agentic:

1) **Request** (UI/API/webhook/cron) creates an execution request.
2) **Persist** an execution row in tenant schema.
3) **Enqueue** Oban job(s) to perform work.
4) **Perform** work with idempotency keys and retries.
5) **Log** execution events and tool calls.
6) **Update** execution status and derived metrics.
7) **Notify** UI/integrations via PubSub/webhooks.

### 6.2 Streaming responses (chat UX)
The architecture can support streaming in two non-exclusive ways:
- **SSE** from Phoenix controller for immediate UX streaming
- **PubSub** + polling/updates for durable progress tracking

**Theory:** streaming is a UI feature; durability is a system feature. Don’t confuse the two. Always persist the execution result regardless of streaming.

### 6.3 LLM provider abstraction
Keep an internal `LLM.Client` boundary:
- provider selection,
- retries,
- structured output extraction,
- cost accounting,
- safety controls.

This keeps providers swappable and makes tests feasible.

---

## 7) Integration architecture theory (how external systems connect)

### 7.1 Integration components (by concern)
For each integration, separate:

- **Auth & credentials**
  - OAuth tokens, refresh flow, secrets storage
- **Inbound**
  - webhooks, email polling/push, event subscriptions
- **Outbound**
  - API calls with rate limiting, retries, circuit breakers
- **Normalization**
  - canonical internal event types and payload shapes
- **Tenant binding**
  - credentials and configuration always scoped to tenant

### 7.2 Rate limiting and resilience
Adopt these patterns:
- per-tenant rate limits (bucketed by integration + endpoint)
- circuit breakers for flaky APIs
- retry with jitter (Oban backoff + custom)
- idempotency for webhook deliveries and outbound side effects
- dead-letter style visibility (failed jobs tied to installation/execution)

### 7.3 Unified inbox / multi-channel messaging (optional future)
If pursued, ensure:
- canonical “message” model,
- channel adapters,
- retention policy and PII controls,
- search/index strategy (later).

### 7.4 MCP interoperability guidance (edge compatibility, not core)
MCP (Model Context Protocol) is a standard for connecting AI applications to external tools and data sources. FleetPrompt should treat MCP as an **interoperability layer at the edges**, while keeping FleetPrompt’s internal core centered on **signals + directives + executions**.

**What this means in practice:**
- FleetPrompt can **consume** MCP servers as tool providers:
  - an execution step/tool call can invoke an MCP tool
  - the invocation must be recorded as part of the execution (tool call record) and must emit signals for auditability
- FleetPrompt can **expose** MCP servers for certain installed packages:
  - a package can “publish” a set of MCP tools backed by vetted, platform-owned handlers
  - MCP calls are treated as external inputs and converted into FleetPrompt directives/executions (not direct side effects)

**Non-negotiables for MCP integration:**
- Never allow MCP callers to select tenant context directly; tenant must be derived from an authenticated binding (session/org, API key → org, or an installation/credential binding).
- Every MCP tool invocation must be:
  - idempotent where possible,
  - attributable (correlation_id/causation_id),
  - observable (signals + execution logs),
  - secret-safe (no tokens in signals/logs).

This approach reduces lock-in risk (FleetPrompt interoperates with the broader tool ecosystem) while preserving FleetPrompt’s differentiation: installation lifecycle, governance, replayability, and multi-tenant reliability.

---

## 8) Security, compliance, and operational posture

### 8.1 Authentication and authorization
Current foundation:
- session-based auth,
- org membership roles (`owner/admin/member`),
- admin UI restricted by role.

Next theory steps:
- formal Ash policies for resources/actions
- separate “platform admin” from “org admin” if needed later
- API keys for machine access (scoped, expiring, rotated)

### 8.2 Secrets handling
Never store raw third-party tokens in logs.
Prefer encryption-at-rest for credential fields.
Keep secrets out of the frontend; only exchange via server.

### 8.3 Auditability
Every installation, execution, and integration action should be traceable:
- who triggered it (user or system),
- when,
- what changed,
- what external calls occurred.

---

## 9) Versioning & evolution theory (critical for packages)

### 9.1 Package versioning
Packages must be:
- versioned (semver-like),
- immutable once published (or “yanked” but not edited),
- installable by exact version.

Installations should record:
- installed package version,
- configuration version,
- migration history.

### 9.2 Schema evolution
Tenant schemas add complexity; commit to:
- forward-only migrations,
- safe defaults for UUIDs and functions,
- idempotent tenant migrations,
- a strategy for migrating installation config data across package versions.

---

## 10) Observability & business metrics (what “done” means)

### 10.1 Minimum telemetry events (recommendation)
Standardize event taxonomy now:

- `fleetprompt.auth.login`
- `fleetprompt.org.select`
- `fleetprompt.package.install.requested`
- `fleetprompt.package.install.completed|failed`
- `fleetprompt.agent.execution.started|completed|failed`
- `fleetprompt.integration.webhook.received|processed|failed`
- `fleetprompt.rate_limit.hit`

Include metadata:
- org_id / tenant schema
- user_id (if applicable)
- package_slug/version
- execution_id
- provider (llm/integration)
- error class

### 10.2 User-visible operational surfaces
Architect toward UI surfaces for:
- executions list + logs
- installation status and errors
- integration health
- usage and cost dashboards

These surfaces are part of trust-building and support.

---

## 11) Current reality check (as of STATUS)

### Implemented (foundation)
- Phoenix + Inertia + Svelte split structure
- Multi-tenancy via schema-per-tenant for core tenant resources (agents)
- Session auth + org membership + org selection
- Ash domains/resources: Accounts, Agents, Skills (+ placeholders for Packages/Workflows)
- Admin UI with tenant selection controls

### Not yet implemented (but planned)
- Package registry resources and installation lifecycle
- Chat streaming and persistence resources (in the Inertia/Svelte UI, not LiveView)
- Agent execution resources, jobs, and LLM integration
- Workflows and workflow executor
- API/SDK/CLI

**Key alignment note:** there is an older LiveView chat implementation doc. The current stack choice is Inertia + Svelte; LiveView should be treated as optional for specific realtime/admin use cases, not the primary UI.

---

## 12) Architectural recommendations (to realign implementation)

These are the changes I recommend making to keep architecture coherent as you proceed.

### 12.1 Commit to one primary UI path for chat
- Primary: **Inertia + Svelte chat page** with SSE streaming.
- Optional: LiveView only if there’s a compelling reason (e.g., operator consoles), but do not fork the product UX across two stacks.

### 12.2 Treat “Package installation” as the spine of integrations
Before building many integrations, build:
- `Package` (global)
- `Installation` (tenant)
- `Installer job` (Oban)
- “integration credential” resource(s) tied to installation

Then integrations become package implementations, not ad hoc features.

### 12.3 Implement persisted signals as a first-class primitive (not “later”)
FleetPrompt’s current plan treats signals as **persisted, tenant-scoped, replayable facts** (not telemetry-only). This is required for package installs, integrations, and workflows to be operable and supportable.

Minimum required components:
- A tenant-scoped `signals` table/resource (immutable events with dedupe, correlation/causation, actor metadata)
- A single “emit” pathway (a SignalBus-style module/service) that:
  - validates payloads,
  - persists the signal,
  - (optionally) publishes PubSub for realtime UX,
  - enqueues durable handlers via Oban
- Replay tooling (admin/support) that can re-enqueue handlers for selected signals/tenants safely

Telemetry and structured logs remain important, but they are **additional outputs**. The persisted signal stream is the durable ground truth that enables:
- install lifecycle auditing,
- safe retries and idempotency,
- integration webhook dedupe,
- “what happened?” debugging in production.

### 12.4 Make idempotency a first-class property
- Webhook ingestion: idempotency key per provider event id.
- Installation: idempotency key per (tenant, package, version).
- Execution: idempotency key per request or trigger.

### 12.5 Define the “tool permission model” early
Agents calling tools need guardrails:
- per-agent allowed tools
- per-installation granted scopes
- per-tenant quotas
- per-user permissions for initiating actions

This prevents security debt later.

---

## 13) Concrete “next architecture” checklist (non-code)

Use this as an architecture gate before pushing into Phase 2/3/4 work.

1) **Package Registry Spec**
   - required metadata fields
   - version semantics
   - config schema representation
   - dependency declaration

2) **Installation Lifecycle Spec**
   - state machine
   - installer job contract
   - failure taxonomy and UI surfaces

3) **Execution Contract**
   - input/output shapes
   - logging schema
   - token/cost accounting requirements

4) **Integration Contract**
   - credential storage model
   - inbound/outbound separation
   - rate limiting and retries

5) **Event/Telemetry Conventions**
   - naming, metadata keys, correlation ids

---

## 14) Definition of architectural success (what you should optimize for)

FleetPrompt’s architecture is “correct” when:

- You can add a new integration package without touching unrelated domains.
- A tenant can safely install/uninstall/upgrade packages with clear visibility.
- Every execution is durable, observable, and attributable (cost, logs, outcome).
- Failures are isolated per tenant and recoverable (retries, compensation).
- The UI remains simple because server contracts are stable and consistent.
- The system can scale operationally (more tenants, more integrations, more jobs) without a rewrite.

---

## Appendix A: Glossary (FleetPrompt-specific)

- **Tenant:** organization context; implemented as `org_<slug>` schema in Postgres.
- **Package:** global, versioned product unit; defines integrations/skills/agents/workflows.
- **Installation:** tenant-owned instance of a package with config and credentials.
- **Skill:** reusable capability unit.
- **Agent:** configured entity that can execute tasks (often using skills/tools).
- **Execution:** durable record of an agent run with logs and metrics.
- **Workflow:** multi-step orchestration of executions and integration actions.

---