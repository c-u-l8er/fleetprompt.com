# FleetPrompt — Implementation Build Prompt
**Version:** 1.0 | **Date:** April 2026 | **Type:** Full Implementation (Phoenix + OTP + Supabase)

---

## Your Mission

You are building **FleetPrompt** — the open agent marketplace for the [&] Protocol ecosystem. FleetPrompt is the registry where production-ready AI agents are published, discovered, and deployed in one click. Every listed agent carries a versioned manifest, a computed trust score, declared permissions, and a linked SpecPrompt spec.

**Read `docs/spec/README.md` fully before writing a single line.** It is the authoritative spec.

FleetPrompt is the **distribution layer** of the dark factory pipeline:
```
SpecPrompt (spec in) → Agentelic (build) → OS-008 (enforce) → FleetPrompt (distribute) → RuneFort (observe)
```

FleetPrompt is also the **canonical trust broker** of the [&] ecosystem — it aggregates PRISM CL scores, test coverage, usage data, and audit quality into a single trust score.

---

## Target Stack

```
Language:     Elixir 1.17+ / OTP 27
Framework:    Phoenix 1.8+ (LiveView for real-time search, PubSub for trust broadcasts)
Database:     PostgreSQL via shared Supabase (fleet.* schema, migration range 030-039)
Search:       pg_trgm + ts_vector (no external search infra)
Hot Cache:    ETS (:fp_manifests, :fp_trust_scores, :fp_search_index, :fp_categories)
Audit:        Broadway pipeline (batched, append-only)
Background:   Oban (trust recompute, webhook delivery, search index refresh)
Auth:         Supabase Auth (shared [&] ecosystem — amp.profiles, amp.workspaces)
Telemetry:    :telemetry + Prometheus
Deploy:       Mix release + Docker on Fly.io
```

---

## Repository Structure

Create this structure inside `fleetprompt.com/`:

```
fleetprompt.com/
├── lib/
│   ├── fleet_prompt/
│   │   ├── agents/
│   │   │   └── agent.ex               # FleetPrompt.Agents.Agent schema (fleet.agents)
│   │   ├── manifests/
│   │   │   └── manifest.ex            # FleetPrompt.Manifests.Manifest schema (fleet.manifests)
│   │   ├── publishers/
│   │   │   └── publisher.ex           # FleetPrompt.Publishers.Publisher schema (fleet.publishers)
│   │   ├── installs/
│   │   │   └── install.ex             # FleetPrompt.Installs.Install schema (fleet.installs)
│   │   ├── trust/
│   │   │   ├── engine.ex              # FleetPrompt.TrustEngine — 4-signal score computation
│   │   │   ├── worker.ex              # FleetPrompt.TrustWorker — GenServer per agent
│   │   │   └── supervisor.ex          # FleetPrompt.TrustSupervisor — DynamicSupervisor
│   │   ├── registry.ex                # FleetPrompt.Registry — manifest CRUD, version management
│   │   ├── search/
│   │   │   ├── index.ex               # FleetPrompt.SearchIndex — pg_trgm + ts_vector management
│   │   │   └── query.ex               # FleetPrompt.Search — search query builder
│   │   ├── forks.ex                   # FleetPrompt.Forks — fork-and-customize workflow
│   │   ├── install_engine.ex          # FleetPrompt.InstallEngine — deploy orchestration
│   │   ├── audit_writer.ex            # FleetPrompt.AuditWriter — Broadway append-only audit
│   │   ├── webhook_dispatcher.ex      # FleetPrompt.WebhookDispatcher — Oban async webhooks
│   │   ├── pipeline_intake.ex         # FleetPrompt.PipelineIntake — dark factory event handler
│   │   └── mcp/
│   │       ├── server.ex              # MCP JSON-RPC server (section 11)
│   │       └── tools.ex               # Tool definitions and handlers
│   ├── fleet_prompt.ex                # Application entry point
│   └── fleet_prompt_web/
│       ├── router.ex                  # Phoenix router
│       ├── live/
│       │   ├── search_live.ex         # LiveView — agent search (⌘K)
│       │   ├── agent_detail_live.ex   # LiveView — agent detail + manifest
│       │   ├── trust_dashboard_live.ex # LiveView — trust score dashboard
│       │   └── publisher_live.ex      # LiveView — publisher profile
│       └── controllers/
│           ├── api_controller.ex      # REST API for programmatic access
│           └── webhook_controller.ex  # POST /api/pipeline/intake (CloudEvents)
├── test/
│   ├── trust/
│   │   ├── engine_test.exs
│   │   └── worker_test.exs
│   ├── search/
│   │   ├── index_test.exs
│   │   └── query_test.exs
│   ├── pipeline_intake_test.exs
│   ├── forks_test.exs
│   └── fixtures/
│       ├── customer_support_manifest.json
│       └── consolidation_event.json
├── mix.exs
├── Dockerfile
└── fly.toml
```

---

## Implementation Order

### Phase 1: Core Registry (weeks 1-6)

1. **Set up Phoenix project** with Ecto, Supabase config, LiveView
2. **Implement Ecto schemas** (sections 3-4)
   - `FleetPrompt.Publishers.Publisher` with workspace_id, user_id (Supabase Auth)
   - `FleetPrompt.Agents.Agent` with workspace_id, search_vector
   - `FleetPrompt.Manifests.Manifest` with all fields from section 4.1
   - `FleetPrompt.Installs.Install` with workspace_id
   - Audit events schema with workspace_id
3. **Implement Registry** (`registry.ex`)
   - Manifest CRUD with version immutability
   - Version management (semver enforcement)
   - Status transitions: draft → published → deprecated → yanked
4. **Implement ETS caches**
   - `:fp_manifests` — agent_id:version → manifest map
   - `:fp_trust_scores` — agent_id → {score, computed_at}
   - `:fp_search_index` — trigram → [agent_id]
   - `:fp_categories` — category_slug → [agent_id]

### Phase 2: Trust Engine (weeks 4-8)

1. **Implement TrustEngine** (`trust/engine.ex`)
   - 4 weighted signals: test_coverage (30%), spec_compliance (25%), usage_history (25%), audit_quality (20%)
   - `compute/1` → integer 0-100
   - Individual signal computations from section 5.1
2. **Implement TrustWorker** (`trust/worker.ex`)
   - GenServer per agent
   - Computes initial score on publish
   - Recomputes on new data (installs, test results, audits)
   - Caches in ETS
   - Broadcasts via PubSub
   - Hibernates after 5 minutes inactivity
3. **Implement TrustSupervisor** — DynamicSupervisor managing TrustWorkers

### Phase 3: Search (weeks 6-10)

1. **Implement full-text search** (section 8)
   - ts_vector generated column on agents (name A, description B, tags C)
   - pg_trgm fuzzy matching indexes
   - `FleetPrompt.Search.search/2` with filters: min_trust, category, runtime, limit
   - Ranking: ts_rank descending, then trust_score descending

### Phase 4: Publish Pipeline (weeks 8-12)

1. **Implement publish flow** (section 6)
   - Manifest validation → spec validation → duplicate check → trust computation → index update → audit + notify
   - Version immutability enforcement
   - Yank support (hides from search, preserves record)
2. **Implement AuditWriter** — Broadway pipeline for batched audit writes
3. **Implement WebhookDispatcher** — Oban worker for async webhook delivery with retry/backoff

### Phase 5: Install Pipeline (weeks 10-14)

1. **Implement install flow** (section 7)
   - Permission review → Delegatic policy check → MCP dependency resolution → OpenSentience deploy → Graphonomous connect → audit + confirm
2. **Implement InstallEngine** (`install_engine.ex`)
   - Permission sandboxing (section 7.2)
   - Delegatic org-level denylists
3. **Implement Fork System** (`forks.ex`) — section 9
   - Fork creates new agent under forker's account
   - `forked_from` provenance tracking
   - Trust score starts at 0 for forks

### Phase 6: Dark Factory Pipeline Intake (weeks 12-16)

1. **Implement PipelineIntake** (`pipeline_intake.ex`) — section 10.2
   - Accept `ConsolidationEvent` from Agentelic at `POST /api/pipeline/intake`
   - Event validation: CloudEvents envelope, workspace_id, artifact_hash
   - Spec hash cross-check against `spec.specs` (SpecPrompt registry)
   - Reject with `SPEC_NOT_REGISTERED` if spec unknown
   - Initial trust score computation from build results
   - Atomic publish: `fleet.agents` + `fleet.manifests` + search index
   - Emit `ConsolidationEvent` to deploy target with `trust_score`
2. **Implement PULSE trust loop** (section 10.1, Loop 2)
   - Subscribe to `ReputationUpdate` from PRISM/AgenTroMatic
   - Re-broadcast recomputed reputation as canonical trust signal

### Phase 7: MCP Server (weeks 14-18)

1. **Implement MCP server** (`mcp/server.ex`)
   - 7 tools: `registry_search`, `registry_publish`, `registry_install`, `registry_inspect`, `registry_versions`, `registry_trust`, `registry_fork`
   - JSON-RPC over HTTP, MCP protocol v2025-03-26

### Phase 8: Supabase Migration (weeks 14-18, parallel)

1. **Create migration** in `ampersand-supabase/migrations/` (range 030-039):
   - `030_fleet_schema.sql` — create schema + tables:
     - `fleet.publishers` (workspace_id, user_id, name, slug, verified, api_key_hash)
     - `fleet.agents` (workspace_id, publisher_id, name, slug, description, tags[], search_vector, status)
     - `fleet.manifests` (agent_id, publisher_id, version, all manifest fields from 4.1)
     - `fleet.installs` (workspace_id, agent_id, manifest_id, runtime_url, status)
     - `fleet.audit_events` (workspace_id, event_type, actor_id, agent_id, metadata)
   - `031_fleet_rls.sql` — workspace-based RLS policies
   - `032_fleet_search.sql` — ts_vector, pg_trgm indexes

### Phase 9: LiveView UI (weeks 16-22)

1. **Agent search** (⌘K) — real-time search with trust score display
2. **Agent detail** — manifest, permissions, trust breakdown, version history, fork button
3. **Trust dashboard** — publisher's agents with trust score trends
4. **Publisher profile** — published agents, verification status

---

## Key Constraints

- **Trust scores are computed, never self-reported.** 4-signal weighted computation only.
- **Published versions are immutable.** No modifications after publish. Fix via new version.
- **FleetPrompt is the canonical trust broker.** PRISM CL scores feed into trust as one input signal — they do not replace trust.
- **Auth is Supabase Auth (shared ecosystem).** NOT Clerk, NOT custom auth. Same identity as all [&] products.
- **All tables prefixed with `fleet.*`** and workspace-scoped with RLS.
- **Fork trust starts at 0.** Forks must earn trust independently.
- **Pipeline intake validates spec_hash** against SpecPrompt registry. Unknown specs rejected.
- **FleetPrompt does NOT make LLM calls.** Trust computation is deterministic.
- **Install requires explicit permission acceptance.** No silent permission grants.

---

## Integration Points

| System | Direction | Protocol | What |
|--------|-----------|----------|------|
| **Agentelic** | Agentelic → FleetPrompt | ConsolidationEvent | Tested agents publish to registry |
| **SpecPrompt** | FleetPrompt → SpecPrompt | Spec validation | Validate spec hash on publish |
| **OpenSentience** | FleetPrompt → OpenSentience | Manifest deploy | One-click install to runtime |
| **Delegatic** | FleetPrompt → Delegatic | Policy check | Org-level install policy enforcement |
| **Graphonomous** | FleetPrompt → Graphonomous | MCP | Memory connection on deployment |
| **PRISM** | PRISM → FleetPrompt | ReputationUpdate | CL scores feed into trust recompute |
| **AgenTroMatic** | AgenTroMatic → FleetPrompt | ReputationUpdate | Reputation deltas from deliberation |

---

## Success Criteria

- [ ] Manifest publish validates spec hash, enforces version immutability, computes initial trust score
- [ ] TrustEngine computes correct 4-signal weighted scores (test fixtures)
- [ ] TrustWorker recomputes on new data, caches in ETS, broadcasts via PubSub
- [ ] Full-text search returns ranked results with trust score and category filters
- [ ] Fork system creates new agent with provenance tracking and zero trust
- [ ] Install pipeline enforces permission review, Delegatic policy check, deploy flow
- [ ] Dark factory intake accepts ConsolidationEvent, cross-checks spec hash, auto-publishes
- [ ] MCP server discovers tools via `tools/list` and executes all 7 tools
- [ ] Audit trail captures all publish, install, fork, trust change events
- [ ] Supabase migration applies cleanly alongside existing `amp.*`, `kag.*`, `rune.*` schemas
- [ ] LiveView search works in real-time with sub-second response
