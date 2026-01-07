# FleetPrompt — Project Theory (Consolidated)

Last updated: 2026-01-06

This document consolidates:
- the current implementation reality (`project_progress`),
- the existing phase plan (`project_plan`),
- the strategic research in `project_research`,
and turns it into a single coherent “project theory”: what FleetPrompt is, why it wins, and how we should build it next.

---

## 1) Executive Summary (What FleetPrompt *is*)

FleetPrompt is a **multi-tenant AI automation platform** built around a **Package Marketplace** of deployable, composable capabilities (“packages” / “skills”) that can operate **inside existing customer systems** (integration-first), while still enabling a premium “standalone” tier later.

**Core bet:** In agentic AI, the durable moat is not the model UI—it’s:
1) integration depth + reliability,
2) composable primitives (signals/skills/directives),
3) distribution + telemetry + governance,
4) a package ecosystem that compounds.

---

## 2) Current Reality (Project Progress Constraints)

### 2.1 What exists today (confirmed in progress docs)
- Split app layout: Phoenix backend + Inertia + Svelte frontend.
- Ash foundation with schema-per-tenant multi-tenancy (organizations → `org_<slug>` schemas).
- Auth + org membership + org selection are implemented and gating admin.
- Core resources are present (Organizations, Users, OrganizationMemberships, Agents tenant-scoped, Skills global).
- AshAdmin works with tenant selection.
- Frontend scaffolding exists (Home/Dashboard/Marketplace/Chat/Login/Register).

### 2.2 What that implies
- FleetPrompt is currently architected as a **server-driven SPA** (Inertia), not a LiveView-first app.
- Any “chat homepage” or “streaming” plan should assume **SSE or WebSockets integrated with Inertia** (not LiveView-only).
- The near-term objective is to turn the existing foundations into an MVP loop that proves *real* value (not just scaffolding):
  Browse packages → install package → package provisions tenant capabilities → run/observe agent workflows → measure value.
- **Non-negotiable addition:** ship at least **one lighthouse package** end-to-end (install → configure → execute → observable outcome) before scaling “marketplace breadth.” This avoids the marketplace chicken-and-egg problem and anchors the ecosystem in a concrete, demoable win.

---

## 3) Product Thesis (Why customers will buy)

### 3.1 The primary customer pain to solve
Most businesses already have a toolchain (email, chat, CRM, ticketing, ecom, accounting, analytics). They don’t want:
- another system of record,
- data migration,
- retraining their team,
- duplicate workflows.

They do want:
- AI that works *inside* their existing tools,
- automation that is observable, safe, and auditable,
- prebuilt “vertical wins” they can install quickly.

### 3.2 The winning model
**Integration-first + packages + orchestration**:
- Packages are opinionated solution modules (not generic workflow nodes).
- FleetPrompt becomes the “AI layer” that coordinates across systems.
- Standalone UI becomes a premium tier later, not the wedge.

### 3.3 Avoided trap (explicit)
Do not pivot to commoditized “website chat widget” as the core. If needed, add it later as *one package* (a channel adapter), not the platform identity.

---

## 4) Strategic Differentiator (What makes FleetPrompt defensible)

FleetPrompt’s defensibility comes from **compounding technical + distribution moats**:

### 4.1 Integration moat
- Reliable connectors are hard: auth, rate limits, retries, webhook drift, pagination, idempotency, partial failures.
- The “boring” engineering is the moat: consistent patterns for connectors and event handling.

### 4.2 Composition moat (Jido-inspired primitives)
A sustainable platform needs a “grammar” for automation:
- Signals: normalized events/messages between packages and systems
- Skills: composable stateful capabilities (namespaced state, deterministic transforms)
- Directives: safe self-modification / dynamic composition (install/enable/disable capabilities)
- Observability: telemetry, replay, audit trails
- Versioning: schema evolution and package upgrades
- Multi-node distribution: later scale-out and isolation
- **Interop compatibility:** treat emerging standards like **MCP (Model Context Protocol)** as an integration/interoperability layer to reduce long-term lock-in risk and to make FleetPrompt packages “exportable” into the broader agent ecosystem.

### 4.3 Marketplace moat
The marketplace compounding effect requires:
- stable package interfaces,
- versioning and migration,
- installation lifecycle,
- trust model (verification, reviews, permissions),
- analytics (what packages deliver measurable ROI).

---

## 5) The Architecture Theory (How the system should work)

### 5.1 North-star architecture
FleetPrompt should converge on an architecture that looks like:

- Tenant boundary:
  - Organizations live in public schema.
  - Tenant data lives in `org_<slug>` schema.
  - “Global registry” entities live in public schema (packages, global skills catalog, etc).

- Platform primitives:
  1) Signal Bus (event system)
  2) Skill runtime (stateful composition + namespaced state)
  3) Package lifecycle (install/upgrade/remove)
  4) Execution engine (agent executions + workflows)
  5) Observability (telemetry + replay + audits)

- Integration adapters:
  - Connectors normalize inbound/outbound events into signals.
  - Connectors are packaged and installed per tenant.

### 5.2 Why this matters
Without a signal/skill layer, “packages” become:
- just records in a DB,
- coupled to ad-hoc code paths,
- hard to replay/debug,
- hard to compose safely,
- fragile during upgrades.

With signals/skills, packages become:
- composable, testable units,
- safe to install and evolve,
- observable in production.

---

## 6) The “Package” Theory (What a package *is*)

A FleetPrompt package is not merely metadata. It is a **contract** plus a **lifecycle**.

### 6.1 Package contract (definition)
A package should define:
- Identity: `slug`, `name`, `version`, `author`, `category`, etc.
- Capabilities:
  - provided skills
  - provided agents/templates
  - provided workflows/templates
  - provided integrations/connectors
- Inputs/Outputs:
  - signals it consumes
  - signals it emits
- Permissions & risk:
  - what external APIs it accesses
  - what data scopes it requires
  - rate limits / cost profile
- Install hooks:
  - tenant provisioning steps
  - default configuration
  - migrations if upgrading from prior versions
- **Execution model (explicit):**
  - **V1 default: metadata-only packages** (safe): packages declare what they install/enable (skills/workflows/templates/connectors) and those map to vetted, platform-owned runtime code.
  - **No arbitrary third-party code execution** in V1. If/when “code-shipping packages” exist, they require a separate security model (signing, sandboxing, permissions, safe upgrades) and should be treated as a later-phase product.
- **MCP compatibility stance (explicit):**
  - packages should be able to **expose tools/data** via MCP (as MCP servers) and/or **consume MCP tools** (as MCP clients) where it reduces integration cost.
  - FleetPrompt’s internal signal/action model should be designed so it can be bridged to MCP concepts cleanly (tools/resources/prompts) without rewriting package interfaces.

### 6.2 Package lifecycle (install/upgrade/remove)
At minimum, lifecycle must support:
- planned install (validated, authorized, queued),
- background installation with idempotency,
- provisioning of tenant resources/config,
- activation (start emitting/consuming signals),
- upgrade path with schema evolution,
- uninstall with cleanup (and optional retention policies).

### 6.3 Trust & governance
Marketplace success requires:
- verification (publisher identity, signed releases, or curated list early on),
- reviews + ratings,
- “permissions” UI (what data it can read/write),
- audit trails and rollback where feasible.

---

## 7) The “Agent” Theory (How agent execution should be framed)

FleetPrompt should treat “agent execution” as a **measured, auditable unit of work**, not as a chat UX.

### 7.1 Execution is a first-class record
Every run should be trackable:
- input/output
- status (queued/running/completed/failed)
- cost, tokens, latency
- tool calls / actions taken
- logs
- correlation IDs tied to signals and workflows

### 7.2 Workflows are orchestrations of executions + conditions
Workflows should:
- coordinate multiple steps (agent runs, connector calls, branching conditions, parallelism),
- support retries and compensation where possible,
- emit signals for downstream packages.

### 7.3 Chat is a surface area, not the engine
Chat can be:
- a command interface to browse/install/execute,
- a debugging surface to inspect signals/executions,
but it must be built on top of the engine primitives (signals/executions/workflows), not replace them.

---

## 8) Integration-First Theory (How integrations fit without overbuilding)

### 8.1 Integration surfaces
Integrations show up as:
- inbound events: webhook → signal
- outbound actions: signal → API call
- synchronization jobs: scheduled polling → signal

### 8.2 The unifying requirement
All integration code should conform to a common pattern:
- normalize external payloads into internal signals,
- apply middleware (auth, rate limiting, redaction),
- persist events needed for replay/audit,
- produce explicit outcomes and error events.

### 8.3 Why Phoenix/BEAM matters
BEAM strengths (concurrency, supervision) are especially valuable for:
- many concurrent integration streams,
- robust retry/isolated failure handling,
- long-running connector processes,
- tenant isolation patterns (supervision trees per tenant later).

### 8.4 MCP compatibility (why it matters and how to use it)
MCP (Model Context Protocol) is emerging as a standard way for AI applications/agents to connect to tools and data sources. FleetPrompt should treat MCP as a **compatibility layer**, not as the internal core:
- FleetPrompt’s internal contract remains: **signals + directives + executions** (auditable, multi-tenant safe).
- MCP becomes a way to **publish/consume tools** at the edges:
  - a FleetPrompt integration package can optionally provide an MCP server surface for its tools/data
  - FleetPrompt can optionally call out to MCP servers for third-party tool access
This reduces long-term risk that “tool connectivity” becomes commoditized by larger platforms, because FleetPrompt can interoperate while still differentiating on installation lifecycle, governance, observability, and multi-tenant reliability.

---

## 9) Missing Architecture Phases (Reconciled with “Jido missing phases”)

The research identifies missing phases that are not optional long-term. The project plan should explicitly integrate them in a staged way:

### Phase A: Signals (Event System)
Add a minimal but real signal layer:
- a canonical `Signal` struct/schema
- publishing + subscribing primitives
- persistence for replay (at least for debugging and audit)
- tenant scoping and correlation IDs

### Phase B: Skills (Composable state)
Define “skills” as:
- namespaced state per agent or per tenant capability
- deterministic transforms from signals/actions
- clear boundaries between packages

### Phase C: Directives (Lifecycle actions)
Define directives such as:
- register/install/enable/disable package
- register/attach skill
- rotate credentials
- update package configuration safely

### Phase D: Testing strategy
Codify:
- property tests for state transitions
- integration tests for package chains
- tenant isolation tests
- connector contract tests with recorded fixtures

### Phase E: Observability/Telemetry
Emit platform events:
- package lifecycle
- signal handling outcomes
- execution durations/cost
- errors categorized by connector/package/tenant
- business metrics (installs, retention, value events)

### Phase F: Versioning & schema evolution
Packages must support upgrades:
- versioned schemas
- migration functions and data migrations
- compatibility checks

### Phase G: Distribution (multi-node)
Not needed immediately, but the design should not block:
- distributed pubsub/eventing patterns
- per-tenant supervisors
- workload placement strategies

---

## 10) Realignment of the Existing Phase Plan (Based on actual progress)

The existing phase docs are directionally correct, but the sequencing and assumptions need alignment with:
- the current Inertia architecture (not LiveView-first),
- the missing primitives required for packages to be “real,”
- the goal of integration-first.

### 10.1 Revised phase map (practical MVP path)

#### Completed (as of current progress)
- Phase 0: foundation (Phoenix + Inertia + Svelte split build)
- Phase 1: core resources + multi-tenancy + basic auth/org context

#### Next: Phase 2 (Marketplace) — but with two “must-add” platform primitives
Phase 2 should be split into:

Phase 2a — Marketplace data model + basic UI
- Implement `Package`, `Installation`, `Review` resources (global vs tenant scoped appropriately).
- Implement browsing/filtering UI.
- Implement “request install” flow that creates an installation record and enqueues a job.

Phase 2b — Minimal platform primitives to make installs meaningful
- Introduce a minimal signal + directive layer to represent:
  - “installation requested”
  - “installation started”
  - “installation completed/failed”
  - “package enabled/disabled”
- Ensure installation is idempotent and emits audit events.

Outcome: marketplace installs do something real and observable.

#### Phase 3 (Chat)
Reframe Phase 3 explicitly as:
- a UX layer that drives package discovery/installation/execution,
- implemented via Inertia + SSE (consistent with current architecture),
- not a core engine dependency.

Note: Any LiveView-only chat plan should be considered legacy unless intentionally reintroduced.

#### Phase 4 (Execution/Workflows)
Phase 4 should be made package-driven:
- executions should be callable by workflows and by signal handlers,
- workflows should emit signals,
- package installs should provision workflow templates and/or agent templates.

#### Phase 5 (API/SDK/CLI)
Only do after Phase 2–4 are stable enough to expose externally:
- API keys and scopes must align with org/tenant boundaries.
- Webhooks should map to signals cleanly.

### 10.2 Where integrations fit (without boiling the ocean)
Integrations should ship as early packages, not bespoke core features:
- Mattermost adapter package
- Proton Mail adapter package (Bridge-based; see operational constraints)
- “Website chat widget” adapter package (optional later)
Each adapter translates events into signals and uses the same lifecycle/install patterns.

---

## 11) Vertical Strategy Theory (How to pick what to build first)

The research explores multiple vertical frameworks. The unifying rule should be:

Choose the vertical where:
- integration density is high (lots of systems to connect),
- recurring workflows exist (repeatable automation value),
- customers can pay and measure ROI,
- marketplace packages can generalize across many customers.

### Recommended near-term vertical posture
- Build “horizontal integration primitives” first (signals, package lifecycle, execution telemetry).
- Launch with 1–2 “meta-advantage” wedges where integrations compound:
  - marketing agencies and/or e-commerce are strong candidates for package breadth,
  - avoid highly regulated verticals until governance/telemetry is mature (or treat them as later tiers).

This is a sequencing recommendation, not a denial of other vertical opportunities.

---

## 12) Key Engineering Principles (Non-negotiables)

### 12.1 Multi-tenancy correctness first
- Tenant boundary bugs are existential.
- Every install/execution/signal must have explicit tenant context.
- Avoid “magic” tenant selection for background jobs; pass tenant explicitly and validate membership where applicable.

### 12.2 Everything important is observable
- If it runs, it logs structured events.
- If it changes state, it emits telemetry.
- If it integrates externally, it is replayable (to the degree possible).

### 12.3 Idempotency everywhere
- Installs, webhooks, retries, and workflow steps must tolerate duplication.
- Use correlation IDs and dedupe keys.

### 12.4 Contracts over convenience
- Stable package interfaces beat fast hacks.
- Invest early in versioning strategy to avoid “marketplace paralysis” later.

---

## 13) Risks & Mitigations

### Risk: Marketplace built before primitives → installs are fake
Mitigation:
- implement minimal signals/directives + installation audit trail as part of Phase 2.

### Risk: Chat becomes the “engine”
Mitigation:
- treat chat as a client to existing APIs and internal primitives; don’t embed business logic only in chat flows.

### Risk: Integrations become bespoke one-offs
Mitigation:
- enforce a connector pattern:
  inbound event → normalize → signal → handlers
  signal → action runner → external call → result signal

### Risk: Over-expanding verticals early
Mitigation:
- ship a small set of high-quality packages that demonstrate ROI, then expand via a repeatable template.

---

## 14) Concrete Next Actions (What I would do next)

1) Lock the revised phase plan structure (Phase 2a/2b).
2) Implement Phase 2a marketplace resources + UI scaffolding.
3) Implement Phase 2b minimal signals + directives for installation lifecycle + audit.
4) Make at least one “real” package that provisions something tenant-visible (agent template + workflow + connector stub).
5) Add telemetry and a replay/debug path for installation + first package workflows.
6) Only then invest in chat streaming UX improvements, because it will have real capabilities to drive.

---

## 15) Open Questions (Need decisions)

1) Package runtime model:
   - Are packages “pure metadata + templates,” or can they ship executable code?
   - If code, how is it sandboxed, verified, and upgraded safely?

2) Signal persistence scope:
   - Persist all signals or only selected classes (errors, lifecycle, external events)?
   - Retention policy per tenant/tier?

3) Marketplace trust model v1:
   - curated packages only, or allow third-party publishing from day one?

4) Integration credential model:
   - how are OAuth tokens stored per tenant/package?
   - how are scopes presented to admins?
   - rotation and revocation UX?

These should be resolved before scaling integrations and third-party packages.

---

## 16) Bottom Line (The Project Theory in one paragraph)

FleetPrompt wins by becoming the most reliable, composable “AI integration layer” that businesses can install into their existing systems via a marketplace of packages. The platform must be built around durable primitives—signals, skills, directives, lifecycle, observability, and versioning—so packages can be installed, composed, replayed, and upgraded safely across tenants. Chat and UI are distribution surfaces on top of that engine, not the engine itself. The next step is to realign Phase 2 to ship a marketplace that installs real, observable capabilities, and then expand into integrations as packages that translate external events into FleetPrompt signals.
