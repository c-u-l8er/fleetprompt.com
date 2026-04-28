# FleetPrompt — User Stories

Canonical user-story catalog. Each story is a Playwright-testable journey covering unit-tested code paths. Used for (a) e2e test generation in `e2e-playwright/tests/user-stories/fleetprompt/`, and (b) as Claude Design input for UI generation.

**Scope:** Agent marketplace with trust scoring, crystallization, install + review.
**Unit-test surface covered:** `test/fleet_prompt/**` (157 tests).

---

## Story 1 · Search and discover an agent

- **Persona:** DevOps engineer looking for production-ready agents
- **Goal:** Find a trusted customer-support agent that meets org security requirements
- **Prerequisite:** Deployer logged in; at least 1 published agent in `fleet.agents`
- **Steps:**
  1. Click ⌘K search bar on marketplace homepage
  2. Type "customer support"; filter `min_trust=70`
  3. View filtered results ranked by trust score
  4. Click an agent card to open detail page
  5. Review manifest, permissions, version history, test results
- **Success:** Agent manifest with trust badge visible; user can verify behavior before install
- **Covers:** `FleetPrompt.Search.*`, trust filter, tsvector ranking — ~20 unit tests
- **UI status:** exists-today
- **Claude Design hook:** Search result card (name · trust badge · description · category tags · test pass rate)

## Story 2 · Install agent with permission review

- **Persona:** Infrastructure team installing an agent into production
- **Goal:** Deploy a vetted agent with explicit permission acceptance + org policy validation
- **Prerequisite:** Agent selected; deployer has org admin role
- **Steps:**
  1. Click "Install" on agent detail page
  2. Review declared permissions (orders:read, refunds:create, graphonomous:*)
  3. Accept permission set
  4. System runs Delegatic policy check + MCP dependency resolution
  5. System deploys manifest to OpenSentience runtime with capability tokens
- **Success:** Agent live in production; permissions enforced at OS runtime; audit event recorded
- **Covers:** `FleetPrompt.InstallEngine` (all 7 steps), `Permission.map_to_tokens`, `Delegatic.policy_check`, `AuditWriter.log` — ~30 unit tests
- **UI status:** exists-today (/ backed by install_engine_test.exs)
- **Claude Design hook:** Permission review modal — per-capability toggle, policy conflict alerts, audit confirmation

## Story 3 · Monitor agent trust score changes

- **Persona:** Marketplace admin tracking agent reputation
- **Goal:** Watch trust scores update in real-time as agents accumulate usage + audit data
- **Prerequisite:** TrustWorker running; at least 1 ReputationUpdate token in flight
- **Steps:**
  1. Navigate to `/trust` dashboard showing all agents
  2. View agents ranked by trust tier (Excellent / Good / Fair / Low)
  3. New test result arrives; TrustWorker recomputes
  4. PubSub broadcasts → LiveView updates without reload
- **Success:** Real-time trust deltas visible across browsers
- **Covers:** `FleetPrompt.Trust.Engine`, `TrustWorker.recompute`, Phoenix.PubSub — ~15 unit tests
- **UI status:** exists-today (backend live; route currently returns 500 in production — known regression)
- **Claude Design hook:** LiveView trust tier cards with animated score transitions + historical sparkline

## Story 4 · Crystallize an interaction trace into a manifest

- **Persona:** Developer who has been coding with Claude
- **Goal:** Convert session interaction traces into a FleetPrompt manifest so another dev can install the skill
- **Prerequisite:** Trace seeded in Graphonomous (via `act.store_trace`); FleetPrompt workspace provisioned
- **Steps:**
  1. Navigate to `/publish`
  2. Click "Crystallize from Graphonomous"
  3. Enter trace_id; submit
  4. System polls Graphonomous (`retrieve.replay`) → runs `Skills.Crystallizer`
  5. Assert draft manifest appears in `/drafts` with `source_id = trace_id`
- **Success:** Manifest row in `fleet.manifests`; crystallization row in `fleet.skill_crystallizations`; idempotent on re-run
- **Covers:** `Skills.Crystallizer` (23 tests) + `PollWorker` (12) + `GraphonomousClient.HTTP` (18) + `InstallEngine` step 4 (9) — **62 unit tests in one user story**
- **UI status:** backend exists; UI planned
- **Claude Design hook:** Publish page with Graphonomous connector widget + manifest preview + idempotency badge

## Story 5 · Publish an agent after build success (webhook flow)

- **Persona:** Agentelic build pipeline emitting ConsolidationEvent to FleetPrompt
- **Goal:** Auto-publish tested manifest once build passes
- **Prerequisite:** Agentelic emits CloudEvent; spec_hash + compiled_tests_hash present
- **Steps:**
  1. Agentelic build succeeds
  2. CloudEvent ConsolidationEvent → FleetPrompt webhook
  3. FleetPrompt validates envelope + workspace_id
  4. Verifies spec_hash via SpecPrompt registry
  5. Atomic write: `fleet.agents` + `fleet.manifests` + search index
- **Success:** Agent searchable within seconds; initial trust score assigned
- **Covers:** `FleetPrompt.PipelineIntake`, `CloudEvent.parse`, `Trust.compute_initial`, atomic registry write — ~25 unit tests
- **UI status:** mcp-only (internal admin feature)
- **Claude Design hook:** Webhook config UI + event inspector (admin pane)

## Story 6 · Fork and customize an agent

- **Persona:** Team customizing a published agent
- **Goal:** Create a private variant with provenance tracking
- **Prerequisite:** Agent viewable; user in a workspace
- **Steps:**
  1. Click "Fork" on agent detail
  2. Enter new name + description
  3. System copies manifest with `forked_from` reference
  4. Fork starts at `trust_score=0` (independent chain)
- **Success:** Fork visible in user's workspace; lineage preserved
- **Covers:** `Forks.create_fork`, `Registry.clone_with_provenance`, `Trust.reset_for_fork`
- **UI status:** planned
- **Claude Design hook:** Fork dialog with parent-attribution banner

---

**Tests to implement first (highest value):** Story 1, Story 4 (crystallize — the dark-factory hero flow), Story 3.
