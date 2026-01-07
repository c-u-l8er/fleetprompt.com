# FleetPrompt — Project Plan (Single Source of Truth)

This document is the **roadmap index** for FleetPrompt. It is the canonical map of what we’re building, in what order, and why. Individual phase documents remain the detailed implementation specs, but **this file owns sequencing, priorities, and “what’s next.”**

---

## 0) Current reality (as-built)

FleetPrompt today is:

- **Backend**: Phoenix + Ash (+ AshPostgres, AshAdmin, AshStateMachine), Oban jobs
- **Frontend**: Svelte + Vite + Inertia (Phoenix serves built assets)
- **UI design system**: shadcn-svelte (https://www.shadcn-svelte.com/) + Tailwind tokens (consistent components + styling)
- **Forum UI reference implementation**: `fleetprompt.com/project_design_forum/` (React prototype) is the visual/UX reference for Phase 6; the real implementation must be built in Svelte using shadcn-svelte components and FleetPrompt’s UI stack (Inertia).
- **Tenancy**: schema-per-tenant (e.g., `org_<slug>`) via `manage_tenant`
- **Auth**: session auth + org membership + org selection (tenant context)

This matters because several older planning artifacts imply a LiveView-first UI. That is **not** the current architecture.

---

## 1) Product theory (why this plan looks like this)

This roadmap is aligned to the research in `fleetprompt.com/project_research/`:

### 1.1 Integration-first, standalone later (premium)
- The winning near-term wedge is **integration packages that work inside existing tools** (Slack/Email/CRM/etc.).
- A “standalone platform” can exist as a **premium bundle**, but shouldn’t block the integration flywheel.

### 1.2 Packages are the moat
- FleetPrompt’s differentiator is not generic chat; it’s **a marketplace of opinionated, verticalized agent systems** (“packages”), installed into a tenant and executed with controls/telemetry.

### 1.3 Website chat is a package, not the product
- We do **not** pivot the business to a commoditized “website chat widget” model.
- If we support website chat, it’s an **integration package** with clear boundaries.

### 1.4 Jido-inspired missing phases become “Platform Hardening”
The Jido research highlights platform primitives we need (signals, skills, directives, telemetry, versioning). We will adopt the **concepts** in FleetPrompt’s architecture (Ash + Oban + Phoenix), without forcing a wholesale rewrite.

---

## 2) Canonical plan documents (and what is “authoritative”)

### Authoritative implementation phases (current architecture)
1. `fleetprompt.com/project_plan/phase_0_foundation_and_setup.md`
2. `fleetprompt.com/project_plan/phase_1_core_resources.md`
3. `fleetprompt.com/project_plan/phase_2_package_marketplace.md`
4. `fleetprompt.com/project_plan/phase_3_chat_interface.md` (Inertia + Svelte + SSE)
5. `fleetprompt.com/project_plan/phase_4_agent_execution.md`
6. `fleetprompt.com/project_plan/phase_5_api_sdk_cli.md`
7. `fleetprompt.com/project_plan/phase_6_agent_native_forum.md` (optional flagship)

### Design system + UI references (implementation requirement)
- The production UI must use **Svelte + shadcn-svelte** as the component system baseline: https://www.shadcn-svelte.com/
- When implementing Phase 6 (Forum UI), use `fleetprompt.com/project_design_forum/` as the **reference design and UX blueprint** (information architecture, component patterns, page layouts), but do not port its React/router assumptions—rebuild the screens in Svelte using shadcn-svelte components and FleetPrompt’s Inertia architecture.

### Non-canonical / historical (do not implement as-is)
- `fleetprompt.com/project_plan/CHAT_LIVEVIEW_IMPLEMENTATION.md`

Reason: it describes a LiveView-based chat implementation, but FleetPrompt’s UI architecture is currently **Inertia + Svelte**.

---

## 3) Project status (truth as of now)

### Completed / substantially complete
- **Phase 0**: split frontend/backend + Vite build pipeline + Inertia wiring
- **Phase 1**: core Ash resources + schema-per-tenant + seeds + AshAdmin
- **Session auth + org membership + org selection** (additional foundation)

### In progress / needs verification
- Inertia client render verification in browser (mount correctness)

### Not started (planned)
- Phase 2: package marketplace resources + installation + UI
- Phase 3: chat (SSE) + conversation persistence (in Ash)
- Phase 4: execution + workflow engine + LLM client + logs/metrics
- Phase 5: JSON:API + API keys + webhooks + SDK/CLI

---

## 4) Realigned roadmap (what we should do next)

### Guiding rule for sequencing
We prioritize the smallest path to:
1) **Install a package into a tenant**
2) **Execute something measurable**
3) **See results + telemetry**
4) **Add an integration package as the wedge**

That means: **Phase 2 → Phase 4 (thin slice) → Phase 3 (UX) → Phase 5 (distribution)**, with “Platform Hardening” woven in.

**Optional flagship (“killer app”) track (guardrailed): Agent-native Forum**
- This is a potential distribution + validation wedge, but it must **not** preempt the platform primitives.
- Rule: only start the forum milestone once **Signals + Directives (A2)** and **Execution thin-slice (B)** are stable enough to power agent participation with auditability and idempotency.

---

## 5) Roadmap by milestone (with exit criteria)

### Milestone A — Marketplace Core (Phase 2A) — “Packages exist”
**Goal:** a tenant can browse packages and install one.

**Deliverables**
- Global `Package` registry resource
- Tenant-scoped `Installation` resource
- Background installer job (Oban)
- Marketplace index + detail pages (Inertia/Svelte)

**Exit criteria**
- Packages visible in UI
- Install triggers an async job
- Installation state transitions are correct (queued → installing → installed/failed)
- Installed package produces tenant data (agents/skills/workflows created or registered)

**Source doc**
- `fleetprompt.com/project_plan/phase_2_package_marketplace.md`

---

### Milestone A2 — Signals + Directives MVP (Phase 2B) — “Installs are real, operable, and replayable”
**Goal:** package installs and core lifecycle actions produce durable, tenant-scoped events and auditable commands.

**Deliverables**
- Minimal **Signal** envelope + conventions (event name taxonomy, required metadata, correlation/causation ids)
- Signal persistence strategy (initially: a durable table suitable for replay/debug)
- Minimal **Directive** model for controlled state changes:
  - `package.install.requested`
  - `package.install.started`
  - `package.install.completed`
  - `package.install.failed`
  - (optional but recommended) `package.enabled` / `package.disabled`
- Installer job emits lifecycle signals and writes a consistent audit trail

**Exit criteria**
- You can answer: “what happened?” for any install (who/when/why/which tenant/which package/version)
- A failed install can be retried idempotently without corrupting tenant state
- Signals can be replayed in a dev/support workflow to reproduce issues

**Source docs**
- `fleetprompt.com/project_research/jido_fleetprompt_missing_phases.md`
- `fleetprompt.com/project_research/jido_implementation_patterns.md`

---

### Milestone A3 — Lighthouse Package (Phase 2C) — “Prove the loop end-to-end”
**Goal:** ship **one real package** that installs into a tenant, provisions visible capability, executes reliably, and produces measurable signals/logs.

**Why this milestone exists**
Without at least one “lighthouse” package, Phase 2 risks becoming a marketplace UI with no undeniable proof of value. This milestone is the answer to the marketplace chicken-and-egg problem: we seed the ecosystem with one credible, end-to-end package.

**Deliverables**
- Choose **one** lighthouse package with the lowest integration risk:
  - Recommended candidates: **Mattermost “Daily Ops/Client Reporting”** OR **Proton Mail “Follow-up Copilot”**
- Package must:
  - install via **Directive** (`package.install`) and emit full lifecycle **Signals**
  - provision something tenant-visible (e.g., agent template + workflow template + installation config)
  - execute on-demand (and optionally on schedule) via the Execution engine
  - emit “value signals” that can be used for GTM proof (e.g., report delivered, follow-up drafted, triage completed)
- Define (and implement minimally) **package execution model constraints** for v1:
  - packages are **metadata + templates** (no third-party arbitrary code execution in v1)

**Exit criteria**
- Install → configure → run completes with:
  - installation signals present and replayable
  - execution logs present and attributable
  - a user-visible output inside the target surface (Slack message / email draft / etc.)
- “Time to first value” target: **< 15 minutes** from install.

**Operational hardening required for the lighthouse package**
- Credential handling strategy is defined (encryption-at-rest for OAuth tokens/secrets; never store secrets in signals)
- Idempotency key scheme is applied for:
  - directives
  - installs
  - external webhook/event ingestion (if used)
- Rate limiting policy exists (at least per-tenant + per-integration-instance)

**Source docs**
- Lighthouse spec (canonical): `fleetprompt.com/project_plan/phase_2c_lighthouse_package.md`
- Credentials/security (canonical): `fleetprompt.com/project_theory/SECURITY_AND_CREDENTIALS.md`
- Tenancy scaling/migration tooling (canonical): `fleetprompt.com/project_theory/TENANCY_SCALING_PLAN.md`

---

### Milestone B — Execution Thin Slice (subset of Phase 4) — “Something runs”
**Goal:** you can execute an agent workflow in a tenant and see logs.

**Deliverables**
- Tenant-scoped `Execution` + `ExecutionLog`
- Minimal LLM client abstraction (even if only one provider initially)
- Agent executor job (Oban) writing logs and final status

**Exit criteria**
- Create execution → background job runs → execution completes/fails deterministically
- Logs show timestamps + status transitions
- Costs/tokens are recorded (even if approximate initially)

**Source doc**
- `fleetprompt.com/project_plan/phase_4_agent_execution.md`

---

### Milestone C — Chat UX (Phase 3, after A+B) — “A friendly operator console”
**Goal:** chat becomes a UI for discovery + install + run.

**Deliverables**
- Conversation + messages persisted (tenant scoped)
- SSE streaming endpoint
- Intent classifier that drives:
  - package search
  - package install
  - agent creation (lightweight)
  - run execution
- UI renders markdown + action buttons

**Exit criteria**
- A user can: “Install X”, then “Run Y” from chat
- Streaming is stable (no broken chunks; reconnect behavior is acceptable)

**Source doc**
- `fleetprompt.com/project_plan/phase_3_chat_interface.md`

---

### Milestone D — Developer Distribution (Phase 5) — “APIs + keys + webhooks”
**Goal:** FleetPrompt becomes integratable and automatable outside the UI.

**Deliverables**
- AshJsonApi router
- API keys + auth plug
- Webhooks system (+ signing)
- Rate limiting (tenant-aware)
- TS SDK + CLI
- API docs page

**Exit criteria**
- An external client can install a package and trigger an execution via API
- Webhook fires on execution completion

**Source doc**
- `fleetprompt.com/project_plan/phase_5_api_sdk_cli.md`

---

### Milestone E — Integration Wedge Package (new, derived from research)
**Goal:** ship one “integration-first” package that demonstrates the strategy.

**Recommendation**
- Start with **Mattermost** (team chat) or **Proton Mail** (email), depending on which is simplest to authenticate and ship safely.
  - Mattermost: prefer **incoming webhooks** or **personal access tokens** (BOT-style integration) for a low-friction first wedge.
  - Proton Mail: integrate via **Proton Mail Bridge** (IMAP/SMTP locally); note Bridge availability depends on Proton plan and introduces operational constraints (a running Bridge instance).
- Treat website chat as “later” and strictly as a package.

**Exit criteria**
- Integration can be enabled/disabled per tenant
- Produces measurable automation (e.g., triage, summaries, follow-ups)
- Clear compliance boundaries (what data is read/written)

**Research sources**
- `fleetprompt.com/project_research/fleetprompt_integration_architecture.md`
- `fleetprompt.com/project_research/fleetprompt_integration_vs_standalone_strategy.md`

---

### Milestone F — Edge Connector (required for Proton Mail Bridge and other “local-only” systems)
**Goal:** enable FleetPrompt to integrate with systems that require a customer-controlled local component (starting with **Proton Mail Bridge**).

**Why this milestone exists**
Proton Mail’s IMAP/SMTP access is typically mediated by **Proton Mail Bridge**, which runs locally. A cloud-only FleetPrompt instance cannot reliably “reach into” that environment. The Edge Connector closes the loop by providing a secure, tenant-bound, customer-operated runner that:
- connects to Proton Mail Bridge locally,
- normalizes events into FleetPrompt **Signals**,
- executes outbound actions (e.g., send email) through local SMTP when needed,
- preserves tenant isolation and auditability.

**Deliverables**
- Edge connector identity + enrollment model:
  - connector registers to one org/tenant (no cross-tenant operation)
  - connector authenticates using a dedicated API key / token scoped to that org
- Secure ingress endpoint(s) in FleetPrompt for edge-originated events:
  - edge → FleetPrompt: emit persisted `signals` (dedupe + correlation_id required)
- Health + lifecycle:
  - connector heartbeat signals (e.g., `edge.connector.heartbeat`)
  - connector version reporting + update policy
- Proton Mail Bridge integration (v1):
  - ingest inbound emails/events (via local IMAP through Bridge)
  - optional outbound SMTP sending (via Bridge)
  - strict secret handling (no raw tokens/credentials in signals/logs)

**Exit criteria**
- A tenant can connect an Edge Connector and see:
  - connector online/offline status
  - a test “edge signal” successfully persisted and replayable
- Proton Mail ingestion produces deduped signals for new messages without leaking content/secrets by default

---

### Milestone G — Website Chat Package (Charla) — “Complete the communication triangle”
**Goal:** complete the “communication triangle” across:
- mailbox (Proton Mail via Edge Connector),
- instant messenger (Mattermost),
- website chat (Charla widget).

**Principle**
Website chat is **not** the business pivot. It is a **channel adapter package** that routes website conversations into FleetPrompt’s signal/execution system, and then into the customer’s chosen surfaces (Mattermost + email workflows).

**Deliverables**
- A “Website Chat (Charla) Adapter” package that:
  - provides installation + configuration UI for a Charla site/property
  - ingests incoming chat events into FleetPrompt as Signals (exact ingestion method depends on Charla’s supported integration surfaces)
  - routes outcomes to Mattermost and/or email workflows via directives/executions
- Operational requirements:
  - tenant-bound credentials/config
  - idempotency + dedupe for message ingestion
  - explicit consent and privacy posture (do not store secrets in signals; avoid storing full message bodies by default unless tenant explicitly opts in)

**Exit criteria**
- A website chat conversation can be:
  - captured as a FleetPrompt signal stream,
  - triaged by a workflow/execution,
  - escalated into Mattermost and/or email,
  - with a durable audit trail and replayability.

---

### Milestone H — Agent-Native Forum (optional flagship) — “Agents are first-class participants”
**Goal:** build (and dogfood) a modern forum where **humans and agents collaborate natively**, using FleetPrompt primitives as the engine and audit layer.

**Why this milestone exists**
This can be FleetPrompt’s “killer app” if it:
- provides a concrete, always-on environment where agents prove value (answering, summarizing, routing, moderating),
- generates organic distribution (community/network effects),
- validates the Signals/Directives/Execution model under real load and messy real-world content.

**Dependencies (non-negotiable)**
- Milestone A2 (Signals + Directives MVP) — agent actions must be auditable and replayable
- Milestone B (Execution Thin Slice) — agents must be able to run and log work reliably
- Security posture for secrets + safety controls (no secrets in signals/logs; explicit side effects via directives)

**Deliverables (MVP)**
- Core forum resources and UI:
  - categories/tags, threads, posts, basic moderation primitives (flag/lock)
  - in-tenant identity/roles mapped to existing org membership (owner/admin/member)
- Forum emits signals for key events (examples):
  - `forum.thread.created`, `forum.post.created`, `forum.post.flagged`, `forum.thread.solved`
- Agent participation surfaces:
  - users can @mention an agent (creates a signal)
  - agents can reply with an attributed post (directive-backed, logged as an execution)
  - confidence + “needs human review” affordances (trust-building)
- At least 2 first-party “forum agents” as installable packages (curated):
  - `forum_faq_agent` (duplicate detection + suggested links)
  - `forum_summary_agent` (thread TL;DR + weekly digest)

**Exit criteria**
- A new thread can trigger a safe agent response path:
  - signal persisted → directive created → execution runs → post created → signals/logs visible
- Admin can replay/inspect agent actions for a thread (debuggable “why did it post this?”)

**Guardrails (focus protection)**
- The forum is a client of FleetPrompt’s primitives, not a reason to invent parallel systems.
- Start without full realtime complexity; add realtime later only if it improves outcomes.

**Source doc**
- `fleetprompt.com/project_plan/phase_6_agent_native_forum.md`

---

## 6) Platform Hardening Track (Jido-inspired, aligned to our stack)

These are not “extra nice-to-haves”; they are what makes packages safe, operable, and composable.

**Clarification (now that Phase 2B exists):**
- **Signals + Directives are no longer “future hardening”** — they are delivered as first-class platform primitives in **Milestone A2 / Phase 2B** (`fleetprompt.com/project_plan/phase_2b_signals_and_directives.md`).
- Security and tenant ops are part of “done,” not later polish:
  - Credentials/security requirements: `fleetprompt.com/project_theory/SECURITY_AND_CREDENTIALS.md`
  - Tenancy scaling + migration tooling plan: `fleetprompt.com/project_theory/TENANCY_SCALING_PLAN.md`

### Hardening 1 — Signals / Event system (implemented via Phase 2B; expand usage over time)
**Why:** packages need durable communication, replay/debugging, and auditability across installs, executions, workflows, and integrations.

**Canonical implementation spec (Phase 2B)**
- `fleetprompt.com/project_plan/phase_2b_signals_and_directives.md`

**Hardening work after Phase 2B (what remains)**
- Extend signal coverage beyond installs into:
  - executions (`agent.execution.*`)
  - workflows (`workflow.run.*`, `workflow.step.*`)
  - integrations (`integration.webhook.*`, `integration.action.*`)
- Ensure signal emission enforces:
  - tenant context invariants
  - dedupe/idempotency conventions
  - redaction rules (no secrets in `data`/`metadata`) — see `fleetprompt.com/project_theory/SECURITY_AND_CREDENTIALS.md`
- Operationalize retention and tenancy fanout:
  - 30-day retention cleanup job per tenant
  - replay tooling and failure visibility that scales with tenant count — see `fleetprompt.com/project_theory/TENANCY_SCALING_PLAN.md`

**Research sources**
- `fleetprompt.com/project_research/jido_fleetprompt_missing_phases.md`
- `fleetprompt.com/project_research/jido_implementation_patterns.md`

---

### Hardening 2 — Skills (composable capabilities)
**Why:** packages should be built from reusable skills.

**Implementation direction**
- Formalize “skill” execution contract and configuration schema
- Map skills into installed packages

---

### Hardening 3 — Directives (implemented via Phase 2B; expand directive taxonomy)
**Why:** controlled state changes (install/upgrade/enable/disable/uninstall, credential rotation, migration repairs) must be explicit, auditable, and retry-safe.

**Canonical implementation spec (Phase 2B)**
- `fleetprompt.com/project_plan/phase_2b_signals_and_directives.md`

**Hardening work after Phase 2B (what remains)**
- Expand directive types beyond `package.install` into:
  - `package.upgrade`
  - `package.enable` / `package.disable`
  - `package.uninstall`
  - (later) `integration.credential.rotate` / `integration.credential.revoke`
  - (later) `tenant.repair.*` (schema drift/orphan remediation) — see `fleetprompt.com/project_theory/TENANCY_SCALING_PLAN.md`
- Enforce directive authorization and secret-handling rules:
  - org admin role gating for directive requests
  - no secret material in directive params/results
  - explicit “side effects require directives” posture — see `fleetprompt.com/project_theory/SECURITY_AND_CREDENTIALS.md`

---

### Hardening 4 — Observability & telemetry
**Why:** production agent systems without telemetry are unshippable.

**Implementation direction**
- Emit telemetry events for installs/executions
- Add dashboards later; start with structured logs + counters

---

### Hardening 5 — Versioning & schema evolution
**Why:** package upgrades will break tenants unless versioning is designed up-front.

**Implementation direction**
- Package schema version + migration hooks
- “Upgrade installation” flow with rollback

---

## 7) Vertical focus (go-to-market alignment)

The plan supports “packages as product,” which is compatible with multiple verticals. To avoid dilution:

### Recommended initial vertical positioning
- **Marketing agencies** and/or **e-commerce operators** as the first strong “meta-advantage” lane.

**Sources**
- `fleetprompt.com/project_research/fleetprompt_meta_advantage_verticals.md`

### Secondary vertical exploration (later)
- Legal/accounting/healthcare/etc. are viable, but should come after the integration/package flywheel is proven.

**Source**
- `fleetprompt.com/project_research/fleetprompt_vertical_opportunities.md`

---

## 8) Risks & decision log (operationally relevant)

### Key risks
- **Architecture drift**: LiveView vs Inertia confusion → enforce this index as canonical.
- **Tenancy correctness**: every tenant-scoped operation must be safely tenant-gated.
- **Integrations security**: OAuth scopes, token storage, audit trails.
- **Package safety**: packages must not become arbitrary code execution without guardrails.

### Decisions (current)
- UI architecture is **Inertia + Svelte** (canonical).
- “Website chat agent” is **not** the business pivot; at most a package.

---

## 9) “Next 2 weeks” recommended focus (execution plan)

1. **Finish Phase 2A backend resources + installer job** (Marketplace Core)
2. **Implement Phase 2B Signals + Directives MVP**:
   - persisted signals table in tenant schemas
   - directive runner job driving installs
   - installation lifecycle signals (requested/started/completed/failed)
   - replay path for support/debugging
3. **Ship Phase 2C lighthouse package (one end-to-end package)**
   - pick Mattermost as the first “integration-first” surface (low-friction via incoming webhooks)
   - ensure install → run → output works inside Mattermost
   - instrument “first value event” signals for GTM proof
4. **Define and scaffold Milestone F Edge Connector (required for Proton Mail Bridge)**
   - define connector enrollment + auth model (tenant-bound)
   - define edge → FleetPrompt ingress endpoint for emitting persisted signals
   - define heartbeat/health signal conventions
   - document the Proton Mail Bridge dependency and operational requirements
5. **Add website chat to the plan as a package (Milestone G)**
   - treat Charla as a channel adapter package (not the business pivot)
   - define the ingestion mechanism and constraints (credentials, dedupe, privacy defaults)
   - define the routing outcomes (escalate to Mattermost, trigger email workflows)
6. **Operational hardening (start now, keep scope tight)**
   - **credential encryption strategy** for integration tokens/secrets (no secrets in signals; encrypted fields at rest) — see `fleetprompt.com/project_theory/SECURITY_AND_CREDENTIALS.md`
   - **idempotency key scheme** conventions for directives, installs, webhooks/events — see `fleetprompt.com/project_plan/phase_2b_signals_and_directives.md`
   - **rate limiting baseline** (at least per-tenant + per-integration-instance) — define baseline limits per channel/package
   - **tenant migration tooling plan** (status tracking, batching, failure visibility; schema-per-tenant scaling guardrails) — see `fleetprompt.com/project_theory/TENANCY_SCALING_PLAN.md`
7. **Implement thin-slice execution** (Phase 4 subset) sufficient to demonstrate “installed package → execution → logs”
8. Only then: **Chat (Phase 3)** as a UX wrapper around those capabilities (do not block Marketplace + Lighthouse on chat)

---

## 10) Appendix: Roadmap table (quick scan)

| Milestone | Theme | Depends on | Primary docs |
|---|---|---|---|
| A | Marketplace Core (2A) | Phase 0–1 | `phase_2_package_marketplace.md` |
| A2 | Signals + Directives MVP (2B) | A | `phase_2b_signals_and_directives.md` |
| A3 | Lighthouse Package (2C) | A + A2 | `phase_2c_lighthouse_package.md` + `SECURITY_AND_CREDENTIALS.md` + `TENANCY_SCALING_PLAN.md` |
| B | Execution Thin Slice | A + A2 + A3 + Phase 1 | `phase_4_agent_execution.md` |
| C | Chat UX (SSE) | A + B | `phase_3_chat_interface.md` |
| D | API/SDK/CLI/Webhooks | A + B (ideally C) | `phase_5_api_sdk_cli.md` |
| E | First integration package | A + A3 + B (and ideally D) | research + new spec to be written |
| F | Edge Connector (Proton Mail Bridge + local systems) | A2 + (ideally B) | (spec to be added; see Proton Bridge notes in plan) |
| G | Website Chat Adapter Package (Charla) | A2 + (ideally B) | `project_research/fleetprompt_vs_charla_strategic_analysis.md` + (spec to be added) |
| H (optional) | Agent-native Forum (flagship app) | A2 + B (and security posture) | `fleetprompt.com/project_plan/phase_6_agent_native_forum.md` |
| Hardening 1–5 | Signals/skills/directives/telemetry/versioning | woven throughout | Jido research docs |

---

## 11) Notes on deployed environment

Production is running on Fly and serving the Inertia entry HTML at `https://fleetprompt.com`. Deployment is managed via `fly.toml` and release migrations. Keep this in mind when adding:
- migrations (must be release-safe)
- background jobs (Oban config in prod)
- secrets (LLM keys, OAuth client secrets)

---