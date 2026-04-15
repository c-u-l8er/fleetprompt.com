# FleetPrompt — The Open Agent Marketplace

Discover, publish, and install production-ready AI agents. Built on trust scores, versioned manifests, and one-click deployment.

## Source-of-truth spec

- `docs/spec/README.md` — FleetPrompt technical specification
- `prompts/BUILD.md` — Implementation build prompt (9 phases)

## Stack

```
Language:     Elixir 1.17+ / OTP 27
Framework:    Phoenix 1.8 (LiveView for UI, PubSub for trust broadcasts)
Database:     PostgreSQL via shared Supabase (fleet.* schema, migrations 030-039)
Search:       pg_trgm + ts_vector (no external search infra)
Hot Cache:    ETS (:fp_manifests, :fp_trust_scores, :fp_search_index, :fp_categories)
Background:   Oban (trust recompute, webhook delivery, search index refresh)
Auth:         Supabase Auth (shared [&] ecosystem — amp.profiles, amp.workspaces)
Deploy:       Mix release + Docker on Fly.io
```

## Build commands

```bash
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test                          # requires running Supabase for DB tests
mix test test/fleet_prompt/       # unit tests (no DB required for most)
```

## Key modules

| Module | Purpose |
|--------|---------|
| `FleetPrompt.Registry` | Agent + manifest CRUD, version immutability, status transitions |
| `FleetPrompt.Trust.Engine` | 4-signal weighted trust computation (test 30%, spec 25%, usage 25%, audit 20%) |
| `FleetPrompt.Trust.Worker` | GenServer per agent — recomputes, caches in ETS, broadcasts via PubSub |
| `FleetPrompt.Trust.Supervisor` | DynamicSupervisor managing TrustWorkers |
| `FleetPrompt.Search` | pg_trgm + ts_vector full-text search with filters |
| `FleetPrompt.Forks` | Fork-and-customize with provenance tracking |
| `FleetPrompt.PipelineIntake` | ConsolidationEvent processing from Agentelic |
| `FleetPrompt.InstallEngine` | Install flow with permission checks |
| `FleetPrompt.AuditWriter` | Append-only audit event recording |
| `FleetPrompt.WebhookDispatcher` | Oban worker for async webhook delivery |
| `FleetPrompt.Cache` | ETS GenServer with 4 named tables |
| `FleetPrompt.MCP.Server` | MCP JSON-RPC server (7 tools) |

## Supabase schema

Tables live in `fleet.*` schema (migrations 030-039 in `ampersand-supabase/migrations/`):
- `fleet.publishers` — marketplace publisher profiles
- `fleet.agents` — agent listings with search_vector
- `fleet.agent_versions` — semver-versioned releases with JSONB manifest
- `fleet.manifests` — typed manifest records (dedicated table, migration 032)
- `fleet.trust_scores` — computed trust per agent
- `fleet.installs` — installation records
- `fleet.categories` — agent taxonomy
- `fleet.audit_events` — append-only audit log

## LiveView pages

- `/` — SearchLive (⌘K agent search with real-time results)
- `/agents/:id` — AgentDetailLive (manifest, trust, version history, permissions)
- `/publishers` — PublisherLive (publisher listing and profiles)
- `/trust` — TrustDashboardLive (trust scores with tier filtering, PubSub updates)

## API endpoints

- `GET /api/health` — health check
- `GET /api/agents/search?q=...` — search with min_trust, category, runtime filters
- `GET /api/agents/:id` — agent detail
- `GET /api/agents/:id/manifests` — version history
- `GET /api/agents/:id/manifests/:version` — specific manifest
- `POST /api/pipeline/intake` — Agentelic ConsolidationEvent intake

## Role in [&] Ecosystem

FleetPrompt is the **distribution layer** and **canonical trust broker**:

```
SpecPrompt (spec) → Agentelic (build) → OS-008 (enforce) → FleetPrompt (distribute) → RuneFort (observe)
```

## Key constraints

- Trust scores are computed, never self-reported (4-signal weighted)
- Published versions are immutable (fix via new version)
- Fork trust starts at 0 (forks earn trust independently)
- FleetPrompt does NOT make LLM calls (trust computation is deterministic)
- Install requires explicit permission acceptance
- All tables workspace-scoped with RLS
