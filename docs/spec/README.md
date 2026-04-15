# FleetPrompt — Ship Agents to the World
## Technical Specification v0.1 (Elixir/OTP)

**Date:** March 25, 2026
**Status:** Draft
**Author:** [&] Ampersand Box Design
**License:** MIT (open core)
**Stack:** Elixir · OTP · Phoenix · Ecto · PostgreSQL

---

## 1. Overview

FleetPrompt is the **open agent marketplace** for the [&] Protocol ecosystem. It is the registry where production-ready AI agents are published, discovered, and deployed in one click. Every listed agent carries a versioned manifest, a computed trust score, declared permissions, and a linked SpecPrompt spec — making FleetPrompt the first marketplace where you know exactly what an agent does before you install it.

FleetPrompt is the **distribution layer** of the [&] Ampersand Box portfolio:

```
SpecPrompt (Standards)    → defines agent behavior as versioned specs
    ↓
Agentelic (Engineering)   → builds, tests, deploys agents against specs
    ↓
OpenSentience (Runtime)   → governs, executes, observes agents locally
    ↓
Graphonomous (Memory)     → continual learning knowledge graphs
    ↓
FleetPrompt (Distribution) ← THIS  ·  Delegatic (Orchestration)
```

### 1.1 The Problem

57% of organizations now have AI agents in production (LangChain State of AI Agents 2026). Gartner predicts 40% of agentic AI projects will be scrapped by 2027. Yet there are **zero open agent marketplaces**. Teams build agents in isolation, rediscover the same patterns, and have no way to share, reuse, or monetize production-quality work. The agent ecosystem today looks like software distribution before package managers — everyone vendoring, nobody sharing.

Closed platforms (Salesforce AgentForce, OpenAI GPT Store) lock agents into proprietary runtimes. Open frameworks (LangGraph, CrewAI) have no distribution story at all. The result: thousands of production agents exist, but no open registry connects builders with deployers.

### 1.2 Design Principles

1. **Manifest-first** — Every agent is defined by a machine-readable manifest. No opaque binaries.
2. **Trust by computation** — Trust scores are derived from tests, audits, and usage — never self-reported.
3. **Permission transparency** — All permissions declared upfront, reviewed on install. No hidden capabilities.
4. **Provenance chain** — Every version links to its SpecPrompt spec, build pipeline, and audit trail.
5. **One-click deploy** — Install means deploy to OpenSentience. No manual wiring.
6. **Open registry** — Public agents are free to publish and install. The marketplace is the commons.
7. **Fork-friendly** — Any public agent can be forked, customized, and republished.

### 1.3 Why Elixir

The registry is a high-read, low-write workload with real-time requirements — exactly where BEAM excels. Phoenix handles search queries and manifest serving with sub-millisecond latency. GenServer processes manage trust score computation as background pipelines. PubSub delivers real-time notifications when agents are updated, deprecated, or flagged. ETS caches hot manifests and search indexes for microsecond lookups. OTP supervision ensures the registry stays up even when individual trust computations or webhook deliveries fail.

### 1.4 One-Liner

> "The open marketplace where production-ready AI agents are published, discovered, and deployed in one click."

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          FLEETPROMPT                                │
│                   Agent Marketplace (Elixir/OTP)                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Phoenix Router                      Phoenix LiveView              │
│   ├── /api/v1/agents/*                └── Agent search (⌘K)        │
│   ├── /api/v1/agents/:id/versions     └── Agent detail + manifest  │
│   ├── /api/v1/agents/:id/install      └── Trust score dashboard    │
│   ├── /api/v1/agents/:id/trust        └── Publisher profile        │
│   ├── /api/v1/publish                 └── Version diff viewer      │
│   └── /api/v1/search                 └── Category browser          │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌───────────────────┐  ┌────────────────┐  ┌──────────────────┐  │
│   │  Registry Core     │  │  Trust Engine  │  │  Install Engine  │  │
│   │                    │  │                │  │                  │  │
│   │  Manifest storage, │  │  GenServer per │  │  Manifest →      │  │
│   │  version control,  │  │  agent. Async  │  │  OpenSentience   │  │
│   │  search indexing,  │  │  recompute on  │  │  deploy. Perms   │  │
│   │  fork management.  │  │  new data.     │  │  review gate.    │  │
│   │  Full-text via     │  │  Scores cached │  │  Delegatic       │  │
│   │  pg_trgm +         │  │  in ETS.       │  │  policy check.   │  │
│   │  ts_vector.        │  │  PubSub on     │  │  Audit trail     │  │
│   │                    │  │  change.       │  │  per install.    │  │
│   └────────┬──────────┘  └───────┬────────┘  └────────┬─────────┘  │
│            │                     │                     │            │
│   ┌────────▼─────────────────────▼─────────────────────▼────────┐  │
│   │                   PostgreSQL (via Ecto)                      │  │
│   │                                                              │  │
│   │  Tables: agents | agent_versions | manifests | trust_scores  │  │
│   │          installs | publishers | categories | audit_events   │  │
│   │  Indexes: ts_vector (search), pg_trgm (fuzzy), trust_score  │  │
│   │           category_id, publisher_id, semver                  │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                       │
│   ┌────────────────────────▼────────────────────────────────────┐  │
│   │                    ETS (hot cache)                           │  │
│   │  :fp_manifests — agent_id:version → manifest map            │  │
│   │  :fp_trust_scores — agent_id → {score, computed_at}         │  │
│   │  :fp_search_index — trigram → [agent_id]                    │  │
│   │  :fp_categories — category_slug → [agent_id]                │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│   External Integrations (by API / MCP)                              │
│   ├── SpecPrompt — spec validation on publish                       │
│   ├── Agentelic — build pipeline publishes tested agents            │
│   ├── OpenSentience — one-click deploy target                       │
│   ├── Delegatic — governance policy enforcement on install          │
│   ├── Graphonomous — memory connection on deployment                │
│   └── WebHost.Systems — hosting infrastructure                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 OTP Supervision Tree

```
FleetPrompt.Application
├── FleetPrompt.Repo (Ecto/Postgres)
├── FleetPromptWeb.Endpoint (Phoenix)
├── FleetPrompt.Registry (GenServer — manifest CRUD, version management)
├── FleetPrompt.SearchIndex (GenServer — pg_trgm + ts_vector management)
├── FleetPrompt.TrustSupervisor (DynamicSupervisor)
│   ├── FleetPrompt.TrustWorker (agent "customer-support-v2")
│   ├── FleetPrompt.TrustWorker (agent "data-pipeline-monitor")
│   └── FleetPrompt.TrustWorker (agent ...)
├── FleetPrompt.InstallEngine (GenServer — deploy orchestration)
├── FleetPrompt.AuditWriter (Broadway — append-only audit events)
├── FleetPrompt.WebhookDispatcher (Oban — async webhook delivery)
└── Phoenix.PubSub (trust score changes, new versions, deprecations)
```

### 2.2 Component Summary

| Component | Responsibility | OTP Pattern |
|-----------|---------------|-------------|
| `FleetPrompt.Registry` | Manifest storage, version control, fork management. Source of truth for all agent metadata. | GenServer |
| `FleetPrompt.SearchIndex` | Full-text search via PostgreSQL ts_vector + pg_trgm. Maintains ETS search cache. | GenServer + ETS |
| `FleetPrompt.TrustWorker` | Computes trust score for a single agent. Recomputes on new data (test results, installs, audits). | GenServer, supervised by TrustSupervisor |
| `FleetPrompt.InstallEngine` | Orchestrates one-click deploy: permission review → Delegatic policy check → OpenSentience deploy → Graphonomous connect. | GenServer |
| `FleetPrompt.AuditWriter` | Batches audit events (publishes, installs, forks, trust changes) to Postgres. Append-only. | Broadway pipeline |
| `FleetPrompt.WebhookDispatcher` | Delivers webhooks for version updates, deprecations, trust score changes. Retry with backoff. | Oban worker |
| `FleetPromptWeb.*` | Phoenix router, controllers, LiveView for search, browse, agent detail, and publisher dashboards. | Phoenix conventions |

---

## 3. Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | Elixir 1.17+ | Unified with [&] portfolio. BEAM handles high-read registry workloads. |
| Framework | Phoenix 1.8+ | LiveView for real-time search. PubSub for trust score broadcasts. |
| Database | PostgreSQL 16+ | Ecto schemas, full-text search (ts_vector), fuzzy matching (pg_trgm). |
| Search | pg_trgm + ts_vector | No external search infra. PostgreSQL handles both fuzzy and ranked full-text. |
| Hot Cache | ETS | Manifest lookups, trust scores, and search indexes in microseconds. |
| Audit Pipeline | Broadway | Batched audit event writes. Back-pressure. Guaranteed delivery. |
| Background Jobs | Oban | Trust recomputation, webhook delivery, search index refresh, deprecation notices. |
| Auth | Supabase Auth (shared ecosystem) → custom Plug | Publisher identity via shared `amp.profiles`. API key management for CI/CD publish flows. Same auth as all [&] products. |
| Telemetry | :telemetry + Prometheus | Search latency, publish throughput, install success rate, trust compute time. |
| Deployment | Mix release + Docker | Single BEAM node or clustered via libcluster. |

---

## 4. Agent Manifests

The agent manifest is the core data structure of FleetPrompt. Every published agent carries a manifest that fully describes what it does, what it needs, and why it can be trusted.

### 4.1 Manifest Schema

```elixir
defmodule FleetPrompt.Manifests.Manifest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fleet.manifests" do
    belongs_to :agent, FleetPrompt.Agents.Agent, type: :binary_id
    belongs_to :publisher, FleetPrompt.Publishers.Publisher, type: :binary_id

    # Identity
    field :name, :string
    field :slug, :string
    field :version, :string                  # semver (e.g. "2.1.0")
    field :description, :string
    field :category, :string
    field :tags, {:array, :string}, default: []

    # Spec linkage
    field :spec_url, :string                 # SpecPrompt SPEC.md URL
    field :spec_hash, :string                # SHA-256 of spec at publish time

    # Permissions (declared upfront)
    field :permissions, {:array, :map}, default: []
    # Each: %{capability: "orders:read", scope: "read", reason: "..."}

    # MCP dependencies
    field :mcp_servers, {:array, :map}, default: []
    # Each: %{name: "graphonomous", url: "...", required: true}

    # Runtime requirements
    field :runtime, :string, default: "opensentience"
    field :min_runtime_version, :string

    # Build provenance
    field :build_pipeline, :string           # "agentelic" | "manual" | "ci"
    field :build_hash, :string               # SHA-256 of build artifact
    field :test_results, :map, default: %{}  # %{passed: 42, failed: 0, skipped: 1}

    # Trust (computed, not declared)
    field :trust_score, :integer             # 0-100, computed by TrustEngine

    # Lifecycle
    field :status, Ecto.Enum,
      values: [:draft, :published, :deprecated, :yanked],
      default: :draft
    field :deprecated_reason, :string
    field :forked_from, :binary_id           # parent manifest ID if forked

    timestamps()
  end

  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [
      :name, :slug, :version, :description, :category, :tags,
      :spec_url, :spec_hash, :permissions, :mcp_servers,
      :runtime, :min_runtime_version,
      :build_pipeline, :build_hash, :test_results,
      :status, :deprecated_reason, :forked_from,
      :agent_id, :publisher_id
    ])
    |> validate_required([:name, :slug, :version, :description, :permissions, :agent_id, :publisher_id])
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$/)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_number(:trust_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:agent_id, :version], name: :manifests_agent_id_version_index)
  end
end
```

### 4.2 Manifest Example (JSON representation)

```json
{
  "name": "customer-support-v2",
  "slug": "customer-support-v2",
  "version": "2.1.0",
  "description": "Handle customer inquiries, process refunds within policy limits, escalate complex issues.",
  "category": "support",
  "tags": ["customer-facing", "e-commerce", "refunds"],
  "spec_url": "https://registry.fleetprompt.com/specs/customer-support-v2/2.1.0/SPEC.md",
  "spec_hash": "sha256:a3f2b9c...",
  "permissions": [
    {"capability": "orders:read", "scope": "read", "reason": "Look up order status and tracking"},
    {"capability": "refunds:create", "scope": "write", "reason": "Process refunds up to $500"},
    {"capability": "notifications:send", "scope": "write", "reason": "Email confirmations"},
    {"capability": "graphonomous:retrieve_context", "scope": "read", "reason": "Recall customer history"},
    {"capability": "graphonomous:learn_from_interaction", "scope": "write", "reason": "Record new knowledge"}
  ],
  "mcp_servers": [
    {"name": "graphonomous", "url": "local://graphonomous", "required": true},
    {"name": "orders-api", "url": "https://orders.internal.company.com", "required": true},
    {"name": "notifications-service", "url": "https://notify.internal.company.com", "required": false}
  ],
  "runtime": "opensentience",
  "min_runtime_version": "0.3.0",
  "build_pipeline": "agentelic",
  "build_hash": "sha256:e7d1f4a...",
  "test_results": {"passed": 42, "failed": 0, "skipped": 1},
  "trust_score": 87,
  "status": "published",
  "forked_from": null
}
```

---

## 5. Trust Engine

Trust scores are the core differentiator of FleetPrompt. They are **computed, never self-reported**, and derived from four weighted signals.

### 5.1 Trust Score Computation

```elixir
defmodule FleetPrompt.TrustEngine do
  @moduledoc """
  Computes trust scores for published agents.
  Score range: 0-100. Recomputed on new data.
  """

  @weights %{
    test_coverage: 0.30,
    spec_compliance: 0.25,
    usage_history: 0.25,
    audit_quality: 0.20
  }

  @type trust_input :: %{
    test_results: %{passed: integer(), failed: integer(), skipped: integer()},
    spec_hash_valid: boolean(),
    spec_sections_complete: float(),
    total_installs: integer(),
    active_installs: integer(),
    install_success_rate: float(),
    avg_uptime: float(),
    audit_events_count: integer(),
    provenance_complete: boolean(),
    permissions_minimal: boolean()
  }

  @spec compute(trust_input()) :: integer()
  def compute(input) do
    test_score = compute_test_score(input)
    spec_score = compute_spec_score(input)
    usage_score = compute_usage_score(input)
    audit_score = compute_audit_score(input)

    raw =
      test_score * @weights.test_coverage +
      spec_score * @weights.spec_compliance +
      usage_score * @weights.usage_history +
      audit_score * @weights.audit_quality

    raw |> round() |> max(0) |> min(100)
  end

  defp compute_test_score(%{test_results: %{passed: p, failed: f, skipped: s}}) do
    total = p + f + s
    if total == 0, do: 0, else: (p / total) * 100
  end

  defp compute_spec_score(%{spec_hash_valid: valid, spec_sections_complete: pct}) do
    base = if valid, do: 50, else: 0
    base + pct * 50
  end

  defp compute_usage_score(%{
    total_installs: total,
    active_installs: active,
    install_success_rate: rate,
    avg_uptime: uptime
  }) do
    install_signal = min(total / 100, 1.0) * 25
    retention_signal = if total > 0, do: (active / total) * 25, else: 0
    rate_signal = rate * 25
    uptime_signal = uptime * 25
    install_signal + retention_signal + rate_signal + uptime_signal
  end

  defp compute_audit_score(%{
    audit_events_count: count,
    provenance_complete: provenance,
    permissions_minimal: minimal
  }) do
    trail_signal = min(count / 50, 1.0) * 34
    provenance_signal = if provenance, do: 33, else: 0
    minimal_signal = if minimal, do: 33, else: 0
    trail_signal + provenance_signal + minimal_signal
  end
end
```

### 5.2 Trust Score Display

| Score | Label | Color | Meaning |
|-------|-------|-------|---------|
| 90-100 | Excellent | Green | Fully tested, spec-compliant, proven in production |
| 70-89 | Good | Blue | Strong coverage, some production history |
| 50-69 | Fair | Yellow | Partial coverage or limited production use |
| 25-49 | Low | Orange | Missing tests or spec gaps |
| 0-24 | Unverified | Red | New or untested agent |

### 5.3 Trust Worker Lifecycle

Each published agent gets a `TrustWorker` GenServer that:
1. Computes initial trust score on publish
2. Recomputes when new data arrives (installs, test results, audits)
3. Caches current score in ETS for sub-microsecond reads
4. Broadcasts score changes via PubSub
5. Hibernates after 5 minutes of inactivity (BEAM reclaims memory)

```
FleetPrompt.TrustSupervisor (DynamicSupervisor)
├── TrustWorker {:agent, "customer-support-v2"}
│   state: %{score: 87, computed_at: ~U[2026-03-25 14:00:00Z]}
├── TrustWorker {:agent, "data-pipeline-monitor"}
│   state: %{score: 92, computed_at: ~U[2026-03-25 13:45:00Z]}
└── TrustWorker {:agent, "invoice-processor"}
    state: %{score: 54, computed_at: ~U[2026-03-25 12:30:00Z]}
```

---

## 6. Publish Pipeline

### 6.1 Publish Flow

```
Publisher (Agentelic CLI / API)
    │
    ▼
┌─────────────────────┐
│  Manifest Validator  │  Validate required fields, semver,
│                      │  permissions format, MCP deps
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Spec Validator      │  Fetch SPEC.md, validate via
│                      │  SpecPrompt parser, compute hash
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Duplicate Check     │  Reject if same agent+version
│                      │  already exists (immutable versions)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Trust Computation   │  Compute initial trust score
│                      │  from test results + spec
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Index Update        │  Update search index, category
│                      │  index, ETS caches
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Audit + Notify      │  Write audit event, broadcast
│                      │  PubSub, fire webhooks
└─────────────────────┘
```

### 6.2 Version Immutability

Published versions are immutable. Once `customer-support-v2@2.1.0` is published, its manifest cannot be modified. To fix a bug, publish `2.1.1`. To deprecate, set status to `:deprecated` with a reason — the manifest remains readable for provenance.

Yanking (`status: :yanked`) hides the version from search and prevents new installs but preserves the record for existing installs and audit trails.

---

## 7. Install Pipeline

### 7.1 Install Flow

```
Deployer (CLI / Web UI)
    │
    ▼
┌─────────────────────┐
│  Permission Review   │  Display all declared permissions.
│                      │  Deployer must explicitly accept.
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Delegatic Policy    │  Check org policies via Delegatic.
│  Check               │  Reject if agent exceeds org
│                      │  allowed runtimes, tools, etc.
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  MCP Dependency      │  Verify all required MCP servers
│  Resolution          │  are available or installable.
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  OpenSentience       │  Deploy agent manifest to target
│  Deploy              │  OpenSentience runtime. Agent
│                      │  starts with sandboxed perms.
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Graphonomous        │  Connect agent to Graphonomous
│  Connect             │  memory. Initialize telespace.
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Audit + Confirm     │  Write install audit event.
│                      │  Return install receipt with
│                      │  agent ID + runtime endpoint.
└─────────────────────┘
```

### 7.2 Permission Sandboxing

Agents cannot exceed their declared permissions at runtime. The install pipeline enforces this by:
1. Extracting permissions from the manifest
2. Mapping them to OpenSentience capability tokens
3. OpenSentience enforces the token boundary — any undeclared API call is rejected
4. Delegatic policies further constrain: org-level denylists override agent permissions

---

## 8. Search

### 8.1 Full-Text Search Architecture

FleetPrompt uses PostgreSQL-native search with no external infrastructure:

```sql
-- ts_vector for ranked full-text search
ALTER TABLE agents ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(array_to_string(tags, ' '), '')), 'C')
  ) STORED;

CREATE INDEX idx_agents_search ON agents USING GIN (search_vector);

-- pg_trgm for fuzzy matching (typo tolerance)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_agents_name_trgm ON agents USING GIN (name gin_trgm_ops);
CREATE INDEX idx_agents_description_trgm ON agents USING GIN (description gin_trgm_ops);
```

### 8.2 Search Query

```elixir
defmodule FleetPrompt.Search do
  import Ecto.Query

  def search(query, opts \\ []) do
    min_trust = Keyword.get(opts, :min_trust, 0)
    category = Keyword.get(opts, :category, nil)
    runtime = Keyword.get(opts, :runtime, nil)
    limit = Keyword.get(opts, :limit, 20)

    base =
      from a in FleetPrompt.Agents.Agent,
        join: m in assoc(a, :latest_manifest),
        where: m.status == :published,
        where: m.trust_score >= ^min_trust

    base
    |> maybe_filter_category(category)
    |> maybe_filter_runtime(runtime)
    |> apply_search(query)
    |> order_by([a, m], [
      desc: fragment("ts_rank(?, plainto_tsquery('english', ?))", a.search_vector, ^query),
      desc: m.trust_score
    ])
    |> limit(^limit)
    |> Repo.all()
  end

  defp apply_search(queryable, nil), do: queryable
  defp apply_search(queryable, term) do
    from [a, m] in queryable,
      where: fragment(
        "? @@ plainto_tsquery('english', ?) OR similarity(?, ?) > 0.3",
        a.search_vector, ^term, a.name, ^term
      )
  end

  defp maybe_filter_category(q, nil), do: q
  defp maybe_filter_category(q, cat), do: from([a, m] in q, where: m.category == ^cat)

  defp maybe_filter_runtime(q, nil), do: q
  defp maybe_filter_runtime(q, rt), do: from([a, m] in q, where: m.runtime == ^rt)
end
```

---

## 9. Fork System

Any public agent can be forked. Forking creates a new agent under the forker's publisher account with `forked_from` set to the source manifest ID.

```elixir
defmodule FleetPrompt.Forks do
  def fork(source_manifest_id, publisher_id, opts \\ []) do
    source = Repo.get!(FleetPrompt.Manifests.Manifest, source_manifest_id)
    new_slug = Keyword.get(opts, :slug, "#{source.slug}-fork")

    %FleetPrompt.Manifests.Manifest{}
    |> FleetPrompt.Manifests.Manifest.changeset(%{
      name: Keyword.get(opts, :name, "#{source.name} (fork)"),
      slug: new_slug,
      version: "0.1.0",
      description: source.description,
      category: source.category,
      tags: source.tags,
      spec_url: source.spec_url,
      permissions: source.permissions,
      mcp_servers: source.mcp_servers,
      runtime: source.runtime,
      publisher_id: publisher_id,
      forked_from: source_manifest_id,
      status: :draft
    })
    |> Repo.insert()
  end
end
```

Fork provenance is tracked and visible: the agent detail page shows "Forked from [original]" with a link. Trust scores for forks start at 0 — forks must earn trust independently.

---

## 10. Integration Points

| Product | Integration | Direction |
|---------|------------|-----------|
| **SpecPrompt** | Specs are validated on publish. SPEC.md URL and hash stored in manifest. Spec changes trigger trust recomputation. | FleetPrompt → SpecPrompt |
| **Agentelic** | Tested agents publish to FleetPrompt via CLI or API. Build pipeline metadata (test results, build hash) included in manifest. | Agentelic → FleetPrompt |
| **OpenSentience** | One-click install deploys manifest to OpenSentience runtime. Agent starts with sandboxed permissions. Runtime reports uptime and usage back to FleetPrompt for trust scoring. | FleetPrompt ↔ OpenSentience |
| **Delegatic** | Install pipeline checks org policies before deployment. Org-level denylists, allowed runtimes, and agent limits are enforced. | FleetPrompt → Delegatic |
| **Graphonomous** | Deployed agents connect to Graphonomous for continual learning memory. Telespace initialized on install. | FleetPrompt → Graphonomous |
| **WebHost.Systems** | Hosting infrastructure for the marketplace web application and API. Convex backend for real-time features (comments, ratings). | FleetPrompt → WHS |

### 10.1 Integration Flow (End-to-End)

```
SpecPrompt                Agentelic              FleetPrompt
   │                         │                       │
   │  SPEC.md authored       │                       │
   │─────────────────────────▶  Build + test agent   │
   │                         │                       │
   │                         │  Publish manifest     │
   │                         │──────────────────────▶│
   │                         │                       │
   │  Validate spec hash     │◀──────────────────────│
   │─────────────────────────▶                       │
   │                         │                       │
   │                         │        Deployer clicks "Install"
   │                         │                       │
   │                         │                       ▼
   │                         │                  ┌─────────┐
   │                         │                  │Delegatic│ Policy check
   │                         │                  └────┬────┘
   │                         │                       │
   │                         │                       ▼
   │                         │              ┌──────────────┐
   │                         │              │OpenSentience │ Deploy
   │                         │              └──────┬───────┘
   │                         │                     │
   │                         │                     ▼
   │                         │              ┌─────────────┐
   │                         │              │Graphonomous │ Memory connect
   │                         │              └─────────────┘
```

---

## 10.1 PULSE Loop Manifest

FleetPrompt declares **two** PULSE-conforming loops under OS-010 because the marketplace has two distinct closed feedback cycles: the **publish loop** (manifest → trust score → discovery) and the **trust loop** (usage outcomes → reputation recompute → re-rank). PULSE supports multiple loops per product through separate manifest files.

### Loop 1: `fleetprompt.publish`

| Phase ID | Kind | Description |
|---|---|---|
| `retrieve_artifact` | `retrieve` | Pull built artifact + manifest from Agentelic via `ConsolidationEvent` |
| `route_validation` | `route` | Choose validation tier: schema-only, deterministic test replay, full live test |
| `act_publish` | `act` | Atomic publish: hash, sign, register, index for search |
| `learn_acceptance` | `learn` | Update publish heuristics from rejection rate and revocation events |
| `consolidate_index` | `consolidate` | Rebuild search index, prune deprecated manifests, archive old versions |

**Cadence:** `event` (artifact arrival from Agentelic). Closure via Postgres, `eventual`.

### Loop 2: `fleetprompt.trust`

| Phase ID | Kind | Description |
|---|---|---|
| `retrieve_signals` | `retrieve` | Pull `ReputationUpdate` + `OutcomeSignal` events from subscribed loops |
| `trust_recompute` | `custom: recompute` | Recompute trust score using test coverage, usage history, audit results, ReputationUpdate deltas |
| `act_rerank` | `act` | Update marketplace ranking + emit revocation if trust falls below threshold |
| `learn_calibration` | `learn` | Calibrate trust weights from confirmed-bad-agent post-mortems |
| `consolidate_scores` | `consolidate` | Periodic score decay; archive historical trust trajectories |

**Cadence:** Primary `cross_loop_signal` (subscribes to `ReputationUpdate` and `OutcomeSignal`), fallback `periodic` (decay).

**Substrates (both loops):**
- `memory`: `graphonomous://workspace/{ws_id}` (trust history, usage patterns)
- `policy`: `delegatic://workspace/{ws_id}`
- `audit`: `delegatic://workspace/{ws_id}/audit`
- `auth`: `open_sentience://workspace/{ws_id}`
- `transport`: `mcp` + `https`
- `time`: optional

**Invariants enabled:** `phase_atomicity`, `feedback_immutability`, `append_only_audit`, `outcome_grounding`, `trace_id_propagation`.

**Cross-loop connections:**
- `fleetprompt.publish` consumes `ConsolidationEvent` from `agentelic.build_pipeline`
- `fleetprompt.trust` consumes `ReputationUpdate` from `agentromatic.deliberation` and any other loop emitting reputation deltas
- `fleetprompt.trust` emits `ReputationUpdate` (re-broadcast after recompute) to all subscribed agent runtimes — making FleetPrompt the **canonical reputation broker** of the [&] ecosystem

**Why this matters:** the FleetPrompt trust loop is the only loop in the portfolio whose primary cadence is `cross_loop_signal`. PULSE's six-cadence model is what makes a pure-signal-driven loop expressible as a first-class citizen, on equal footing with event-driven and streaming loops.

### 10.2 Dark Factory Pipeline Intake

FleetPrompt receives `ConsolidationEvent` from Agentelic when a build succeeds. The intake protocol:

1. **Event validation:** Verify CloudEvents envelope, check `workspace_id` matches a registered workspace, validate `artifact_hash`
2. **Spec hash cross-check:** Pull `spec_hash` from the event, verify it matches a known spec in `spec.specs` (SpecPrompt registry). If the spec is unknown, reject with `SPEC_NOT_REGISTERED`.
3. **Trust computation:** Initial trust score computed from:
   - Test coverage from Agentelic build results (30%)
   - Spec compliance from SpecPrompt validation (25%)
   - Usage history: 0 for new agents (25%)
   - Audit quality from build provenance completeness (20%)
4. **Publish:** Atomic write to `fleet.agents` + `fleet.manifests` + search index update
5. **Emit:** `ConsolidationEvent` to deploy target (OpenSentience/WebHost) with `trust_score` included

**Trust × PRISM reconciliation:** Both FleetPrompt and PRISM compute reputation-like scores, but they are distinct:
- **FleetPrompt trust** = marketplace trust (can I safely install this agent?)
- **PRISM CL scores** = cognitive capability (how well does this agent learn/reason?)
- **Reconciliation:** PRISM `ReputationUpdate` tokens feed into FleetPrompt's trust recompute as one input signal (via the trust loop's `retrieve_signals` phase). FleetPrompt is the **canonical trust broker** — it aggregates PRISM signals alongside test coverage, usage, and audit data. PRISM does not replace FleetPrompt trust; it informs it.

---

## 11. MCP Tools

FleetPrompt exposes itself as an MCP server for programmatic registry access:

| Tool | Description | Parameters |
|------|------------|------------|
| `registry_search` | Search agents by capability, domain, or trust score | `query: string, min_trust: int, category: string, runtime: string, limit: int` |
| `registry_publish` | Publish a tested agent with manifest to the registry | `manifest: map, spec_url: string, test_results: map` |
| `registry_install` | Deploy an agent manifest to an OpenSentience runtime | `agent_id: string, version: string, runtime_url: string, accept_permissions: bool` |
| `registry_inspect` | View agent manifest, permissions, trust score, and provenance | `agent_id: string, version: string \| "latest"` |
| `registry_versions` | List version history for an agent with changelogs | `agent_id: string, limit: int` |
| `registry_trust` | Query or force-recompute trust score for an agent | `agent_id: string, recompute: bool` |
| `registry_fork` | Fork a public agent for customization | `agent_id: string, version: string, new_slug: string` |

### 11.1 MCP Server Implementation

```elixir
defmodule FleetPrompt.MCP.Server do
  @moduledoc """
  MCP server exposing FleetPrompt registry tools.
  Built on the [&] Protocol MCP conventions.
  """

  use AnubisMCP.Server

  @impl true
  def list_tools do
    [
      %{
        name: "registry_search",
        description: "Search the FleetPrompt agent registry",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Search query"},
            min_trust: %{type: "integer", default: 0, description: "Minimum trust score (0-100)"},
            category: %{type: "string", description: "Filter by category"},
            runtime: %{type: "string", description: "Filter by target runtime"},
            limit: %{type: "integer", default: 20, description: "Max results"}
          },
          required: ["query"]
        }
      },
      %{
        name: "registry_publish",
        description: "Publish an agent manifest to the registry",
        input_schema: %{
          type: "object",
          properties: %{
            manifest: %{type: "object", description: "Agent manifest"},
            spec_url: %{type: "string", description: "SpecPrompt SPEC.md URL"},
            test_results: %{type: "object", description: "Test pass/fail/skip counts"}
          },
          required: ["manifest"]
        }
      },
      %{
        name: "registry_install",
        description: "Deploy an agent to an OpenSentience runtime",
        input_schema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            version: %{type: "string", default: "latest"},
            runtime_url: %{type: "string", description: "OpenSentience runtime endpoint"},
            accept_permissions: %{type: "boolean", description: "Explicit permission acceptance"}
          },
          required: ["agent_id", "runtime_url", "accept_permissions"]
        }
      },
      %{
        name: "registry_inspect",
        description: "View agent manifest, permissions, and trust score",
        input_schema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            version: %{type: "string", default: "latest"}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "registry_versions",
        description: "List version history for an agent",
        input_schema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            limit: %{type: "integer", default: 10}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "registry_trust",
        description: "Query or recompute trust score for an agent",
        input_schema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            recompute: %{type: "boolean", default: false}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "registry_fork",
        description: "Fork a public agent for customization",
        input_schema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            version: %{type: "string", default: "latest"},
            new_slug: %{type: "string", description: "Slug for the forked agent"}
          },
          required: ["agent_id", "new_slug"]
        }
      }
    ]
  end

  @impl true
  def call_tool("registry_search", args) do
    results = FleetPrompt.Search.search(
      args["query"],
      min_trust: args["min_trust"] || 0,
      category: args["category"],
      runtime: args["runtime"],
      limit: args["limit"] || 20
    )
    {:ok, format_search_results(results)}
  end

  def call_tool("registry_install", %{"accept_permissions" => false} = _args) do
    {:error, "Permission acceptance required. Review permissions via registry_inspect first."}
  end

  def call_tool("registry_install", args) do
    FleetPrompt.InstallEngine.install(
      args["agent_id"],
      args["version"] || "latest",
      args["runtime_url"]
    )
  end

  # ... remaining tool handlers follow the same pattern
end
```

---

## 12. Data Model

### 12.1 Agents

```elixir
defmodule FleetPrompt.Agents.Agent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fleet.agents" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :tags, {:array, :string}, default: []
    field :search_vector, FleetPrompt.TSVector  # generated column

    belongs_to :publisher, FleetPrompt.Publishers.Publisher, type: :binary_id
    belongs_to :workspace, Amp.Workspaces.Workspace, type: :binary_id  # amp.workspaces — scopes agent visibility
    has_many :manifests, FleetPrompt.Manifests.Manifest
    has_many :installs, FleetPrompt.Installs.Install

    timestamps()
  end
end
```

### 12.2 Publishers

```elixir
defmodule FleetPrompt.Publishers.Publisher do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fleet.publishers" do
    field :name, :string
    field :slug, :string
    field :email, :string
    field :user_id, :binary_id                # References amp.profiles (Supabase Auth)
    field :api_key_hash, :string
    field :tier, Ecto.Enum, values: [:free, :pro, :enterprise], default: :free
    field :verified, :boolean, default: false

    belongs_to :workspace, Amp.Workspaces.Workspace, type: :binary_id  # amp.workspaces
    has_many :agents, FleetPrompt.Agents.Agent

    timestamps()
  end
end
```

### 12.3 Installs

```elixir
defmodule FleetPrompt.Installs.Install do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fleet.installs" do
    belongs_to :agent, FleetPrompt.Agents.Agent, type: :binary_id
    belongs_to :manifest, FleetPrompt.Manifests.Manifest, type: :binary_id
    belongs_to :deployer, FleetPrompt.Publishers.Publisher, type: :binary_id
    belongs_to :workspace, Amp.Workspaces.Workspace, type: :binary_id  # amp.workspaces — install scope

    field :runtime_url, :string
    field :status, Ecto.Enum,
      values: [:pending, :deploying, :active, :failed, :uninstalled],
      default: :pending
    field :permissions_accepted_at, :utc_datetime
    field :delegatic_policy_check, :map, default: %{}
    field :opensentience_agent_id, :string
    field :graphonomous_telespace_id, :string

    timestamps()
  end
end
```

### 12.4 Audit Events

```elixir
defmodule FleetPrompt.Audit.Event do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "fleet.audit_events" do
    field :workspace_id, :binary_id       # amp.workspaces — audit scope (required for compliance)
    field :action, :string  # "publish" | "install" | "fork" | "deprecate" | "yank" | "trust_change"
    field :target_type, :string
    field :target_id, :string
    field :actor_id, :binary_id
    field :metadata, :map, default: %{}
    field :previous_value, :map
    field :new_value, :map

    timestamps(updated_at: false)  # INSERT ONLY
  end
end

# AuditWriter: Broadway pipeline, batch inserts, no updates/deletes ever.
```

---

## 13. Pre-Phase Feasibility Validation (Weeks 0-2)

Before committing to the full implementation roadmap, validate the four highest-risk assumptions:

| Gate | Validates | Pass Criteria | Fallback |
|------|-----------|---------------|----------|
| **FV-1: Trust Score Convergence** | That the 4-signal weighted trust formula produces meaningful differentiation across a synthetic population of 200 agents with varied test/usage/audit profiles | Gini coefficient > 0.3 across computed scores; no more than 20% of agents clustered in any 10-point band | Adjust weights or add sub-signals (e.g., permission minimality bonus, deprecation penalty) |
| **FV-2: Search Latency at Scale** | PostgreSQL ts_vector + pg_trgm search performance with 10K agents and 50K manifests | p99 < 50ms for full-text + fuzzy combined query; index size < 500MB | Add materialized view for hot search results; consider pgvector semantic search as secondary ranker |
| **FV-3: Install Pipeline E2E** | End-to-end install (permission review → Delegatic check → OpenSentience deploy → Graphonomous connect) completes within budget | Install p99 < 10s; all 4 integration points reachable via MCP | Stub unreachable integrations with async completion; degrade gracefully (install without Graphonomous connect if unavailable) |
| **FV-4: ETS Cache Invalidation** | That ETS cache for manifests and trust scores stays consistent under concurrent publish + trust recompute + search workloads | Zero stale reads after 1s of write; no ETS table growth beyond 2GB for 10K agents | Switch to `:ets.select` with version counters; add periodic full-refresh Oban job |

### 13.1 Acceptance Test Criteria

Acceptance tests derived from spec invariants. Each maps to a verifiable assertion:

**Publish Pipeline:**
- Given a valid manifest with all required fields → publish succeeds and manifest is searchable within 2s
- Given a manifest with duplicate `{agent_id, version}` → publish is rejected with `:duplicate_version` error
- Given a manifest with invalid semver → publish is rejected with `:invalid_version` error
- Given a manifest with `spec_url` → spec is fetched, validated via SpecPrompt parser, and `spec_hash` is computed
- Given a published manifest → manifest is immutable; any update attempt returns `:version_immutable`

**Trust Engine:**
- Given an agent with 42 passed / 0 failed / 1 skipped tests → test_score component = 97.67
- Given an agent with `spec_hash_valid: true` and `spec_sections_complete: 0.8` → spec_score = 90
- Given a trust score change → PubSub broadcast is emitted within 100ms
- Given a TrustWorker with no activity for 5 minutes → GenServer hibernates (`:erlang.hibernate`)

**Install Pipeline:**
- Given `accept_permissions: false` → install is rejected with `:permissions_not_accepted`
- Given a Delegatic policy that denies the agent's runtime → install is rejected with `:policy_violation`
- Given a successful install → audit event with action `"install"` is written within 1s
- Given all MCP dependencies marked `required: true` → install fails if any are unreachable

**Search:**
- Given a query matching agent name → result appears in top 3 with ts_rank weight 'A'
- Given a misspelled query with similarity > 0.3 → fuzzy match returns the correct agent
- Given `min_trust: 70` filter → no results with trust_score < 70

**Fork System:**
- Given a forked agent → `forked_from` references the source manifest ID
- Given a forked agent → trust_score starts at 0 (no inherited trust)

### 13.2 `&govern` Integration

FleetPrompt integrates with the `&govern` primitive at two points:

**`&govern.identity` — Agent Registration on Publish:**
When an agent is published, FleetPrompt registers the agent's identity via the `&govern.identity.register` operation:
- `manifest_hash`: SHA-256 of the published manifest
- `spec_hash`: SHA-256 of the linked SpecPrompt SPEC.md
- `capabilities`: extracted from the manifest's `permissions` array
- `publisher_id`: FleetPrompt publisher reference
- `trust_score`: computed score at publish time

This enables cross-runtime identity verification — any OpenSentience instance can verify an agent's identity against FleetPrompt's registry via `&govern.identity.verify`.

**`&govern.telemetry` — Install and Usage Telemetry:**
FleetPrompt emits telemetry events via `&govern.telemetry.emit` for:
- `agent.published` — new version available
- `agent.installed` — successful deployment
- `agent.uninstalled` — agent removed
- `trust.recomputed` — score changed

These events feed into the ecosystem-wide observability layer and contribute to Delegatic's `budget_check` accounting.

---

## 14. Implementation Roadmap

### Phase 1: Core Registry (Weeks 3-8)
- [ ] Ecto schemas + migrations (agents, manifests, publishers, installs, audit_events)
- [ ] Registry GenServer with manifest CRUD and version management
- [ ] Publish pipeline: validation, duplicate check, initial trust computation
- [ ] PostgreSQL full-text search (ts_vector + pg_trgm)
- [ ] Phoenix REST API (search, publish, inspect, versions)
- [ ] AuditWriter Broadway pipeline

### Phase 2: Trust Engine (Weeks 9-12)
- [ ] TrustEngine computation module (four-signal weighted scoring)
- [ ] TrustSupervisor + TrustWorker GenServers (per-agent async recompute)
- [ ] ETS cache for trust scores
- [ ] PubSub broadcasts on trust score changes
- [ ] Trust score display in API responses

### Phase 3: Install Pipeline (Weeks 13-18)
- [ ] Permission review flow (manifest → permission list → explicit accept)
- [ ] Delegatic policy check integration
- [ ] OpenSentience deploy integration (manifest → runtime)
- [ ] Graphonomous memory connection on deploy
- [ ] Install tracking and status management

### Phase 4: Web UI (Weeks 19-24)
- [ ] Phoenix LiveView: agent search (⌘K)
- [ ] Agent detail page (manifest, permissions, trust score, versions)
- [ ] Publisher dashboard (published agents, install stats, trust trends)
- [ ] Category browser
- [ ] Version diff viewer
- [ ] One-click install button with permission review modal

### Phase 5: Fork System + MCP (Weeks 25-30)
- [ ] Fork creation and provenance tracking
- [ ] MCP server with all seven tools
- [ ] Webhook dispatcher (Oban) for version updates and deprecations
- [ ] CLI tool for publish/install/search

### Phase 6: Enterprise (Weeks 31-38)
- [ ] Private registries (isolated namespace, custom trust policies)
- [ ] Team collaboration (shared publisher accounts, RBAC)
- [ ] SSO/SAML via Supabase Auth (enterprise SSO providers)
- [ ] Advanced trust policies (org-specific weight overrides)
- [ ] SLA monitoring and compliance exports

---

## 15. Pricing

| Tier | Price | Features |
|------|-------|----------|
| **Free** | $0/mo | Publish + install public agents. Community trust scores. 10 published agents. Basic search. |
| **Pro** | $29/mo | Private agents. Priority search placement. 100 published agents. Webhook notifications. Trust score analytics. Team collaboration (up to 5). |
| **Enterprise** | Custom | Custom private registries. SSO/SAML. Advanced trust policies (custom weights). Unlimited agents. SLA. Dedicated support. Compliance exports. |

### 15.1 Marketplace Fees

FleetPrompt does **not** charge transaction fees on free agents. For paid agents (future feature — publishers may charge for premium agents):
- Free tier publishers: 15% marketplace fee
- Pro publishers: 10% marketplace fee
- Enterprise: custom terms

### 15.2 Revenue Projections

| Year | Free Publishers | Pro Publishers | Enterprise | ARR |
|------|----------------|----------------|------------|-----|
| Y1 | 500 | 80 | 2 | $128K |
| Y2 | 2,000 | 300 | 8 | $465K |
| Y3 | 5,000 | 800 | 20 | $1.08M |
| Y5 | 15,000 | 2,500 | 50 | $3.2M |

---

## 16. Success Metrics

| Metric | MVP (9 months) | PMF (18 months) |
|--------|----------------|-----------------|
| Published agents | 200+ | 2,000+ |
| Monthly installs | 500+ | 10,000+ |
| Registered publishers | 100+ | 1,000+ |
| Avg trust score (published) | 55+ | 70+ |
| Search p99 latency | < 50ms | < 20ms |
| Install success rate | 90%+ | 97%+ |
| Pro subscribers | 30+ | 300+ |
| Enterprise clients | 2+ | 8+ |

---

## 17. Performance Targets

| Operation | Target |
|-----------|--------|
| Search query (PostgreSQL + ETS) | < 20ms p99 |
| Manifest lookup (ETS hot) | < 5us p99 |
| Trust score read (ETS) | < 1us p99 |
| Trust score recompute | < 500ms p99 |
| Publish pipeline (end-to-end) | < 3s p99 |
| Install pipeline (end-to-end) | < 10s p99 |
| Audit write throughput (Broadway) | > 5K events/sec |

---

*FleetPrompt: Ship agents to the world.*

*[&] Ampersand Box Design — fleetprompt.com*
