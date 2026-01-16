# FleetPrompt — Tenancy Scaling Plan & Migration Tooling

Last updated: 2026-01-06  
Scope: architecture + operations + build plan (not code)

This document defines how FleetPrompt should scale and operate **schema-per-tenant** multi-tenancy over time, including a concrete plan for **tenant migrations**, **connection management**, **observability**, and a future **hybrid tenancy** option (schema-per-tenant for enterprise; shared-schema/RLS for SMB) if/when scale demands it.

This is written to fit FleetPrompt’s current stack:
- Phoenix + Ash + AshPostgres (schema-per-tenant via `manage_tenant`)
- Oban for background jobs
- Postgres as primary store

---

## 1) Current tenancy model (baseline)

### 1.1 Model
- Public schema holds platform identity + registry:
  - `organizations`, `users`, `organization_memberships`, (future: `packages`, `api_keys`, etc.)
- Each org has a dedicated schema:
  - `org_<slug>` (tenant schema)
- Tenant-scoped resources use `multitenancy :context` and run against the selected tenant schema.

### 1.2 Why we keep this model now
Schema-per-tenant is correct at current scale because it provides:
- strong blast-radius isolation
- simpler “export/restore a customer” story
- easier compliance narrative (compared to shared-schema early on)
- alignment with Ash’s tenant primitives and your existing implementation

### 1.3 Known costs
Schema-per-tenant introduces operational and scaling costs:
- migrations must be applied across N schemas
- failed tenant migrations create partial states
- some DB maintenance (vacuum/analyze) scales with tenant count
- connection pooling and job concurrency must be managed to avoid saturation

This plan is designed to make those costs manageable and observable.

---

## 2) Tenancy scaling risks (what can go wrong)

### 2.1 “Migration fanout” risk
Every schema change to tenant-scoped tables implies N schema changes. Without tooling:
- deployments become risky
- one tenant with a broken schema can block progress
- rollback is hard (DDL rollback across N schemas is frequently unsafe)

### 2.2 Connection exhaustion / thundering herd
Even if Postgres handles many concurrent queries, connection limits can be hit if:
- each web request uses separate connections
- background jobs fan out across tenants simultaneously
- tenant migrations run concurrently with high traffic

### 2.3 Noisy neighbors
Schema-per-tenant reduces data collision, but **does not** automatically prevent one tenant from consuming:
- job throughput
- DB CPU/IO
- LLM/API spend
- integration rate limits

You still need:
- per-tenant concurrency controls
- per-tenant rate limiting
- cost visibility and enforcement

### 2.4 Tenant “drift” and orphan schemas
Common failure modes:
- schema created but org row missing
- org row exists but schema not created
- migrations applied partially
- schema exists with stale extensions/functions

You must treat schema lifecycle as a workflow with reconciliation.

---

## 3) “Tenancy SLOs” (what you should measure and enforce)

Define these operational targets to know when your tenancy model is healthy:

### 3.1 Migration SLOs
- **Tenant migration success rate:** ≥ 99.9% per release
- **P95 tenant migration time:** ≤ 30 seconds per tenant (goal; may be higher early)
- **Max concurrent tenant migrations:** controlled (see §6)

### 3.2 Availability / correctness
- **Cross-tenant data leak incidents:** 0 (existential)
- **Tenant context missing on tenant-scoped operations:** 0 (treat as bug)

### 3.3 Platform load
- **DB connections:** stable under load (no exhaustion events)
- **Oban queue latency:** within expected bounds (no runaway queues)
- **Per-tenant job concurrency:** bounded (no single tenant monopolizes)

---

## 4) Tenant migration tooling (what must exist from day 1)

FleetPrompt needs explicit migration tooling. “Run migrations” is not enough.

### 4.1 Tenant migration registry table (public schema)
Create a public “ledger” of migration runs so you can answer:
- Which tenants are on which tenant-schema version?
- Did tenant X fail the last migration? Why?
- Can I safely enable new features for tenant X?

Recommended table (public schema): `tenant_migration_runs`

Suggested fields:
- `id` uuid
- `release_version` string (your app version / git sha)
- `tenant_schema` string (`org_acme`)
- `status` enum: `queued | running | completed | failed | skipped`
- `started_at`, `completed_at`
- `error_kind`, `error_message`, `error_details` (jsonb)
- `attempt` integer
- `migration_kind` enum: `tenant_schema_migrations | tenant_extensions | tenant_repair`
- `correlation_id` string (for tracing across signals/logs/jobs)

Why public schema?
- You can observe across all tenants without changing tenant context.
- You can build an admin “migration dashboard” safely.

### 4.2 Tenant migration job (Oban) — one tenant per job
Migrations should run via durable background jobs:
- Each job migrates a single tenant schema.
- Jobs are retryable, with bounded attempts.
- Jobs record outcomes to `tenant_migration_runs`.

This avoids:
- a single long-running process failing mid-fanout
- manual coordination
- inability to retry one tenant safely

### 4.3 Release workflow (“migrate public first, then tenants”)
On deploy:
1) Apply public schema migrations (platform tables).
2) Enqueue tenant migration jobs for all tenants (or only those needing changes).
3) Continue serving traffic (ideally) while tenant migrations progress, with feature gating.

Key: tenant migrations must be compatible with running code during rollout (see §5).

### 4.4 Feature gating by tenant schema version
Do not assume all tenants are migrated instantly. You need:
- a way to detect tenant schema version readiness
- the ability to disable new features for tenants not yet migrated

This can be as simple as:
- check latest successful tenant migration run for tenant schema
- store a computed “tenant_schema_version” in public org row or cache

---

## 5) Schema evolution strategy (how to avoid breaking tenants)

### 5.1 “Expand → migrate → contract” pattern
Avoid breaking running code by using a 3-step pattern:
1) **Expand:** add new columns/tables, keep old ones.
2) **Migrate:** backfill data gradually (jobs).
3) **Contract:** remove old columns only after all tenants have migrated and code no longer relies on them.

This is critical with tenant fanout.

### 5.2 Avoid destructive DDL in tenant migrations
Whenever possible:
- avoid dropping columns in the same release you add replacements
- avoid renaming columns without compatibility layers
- avoid blocking locks on large tables (use batching/backfills)

### 5.3 Idempotent tenant migrations
Tenant schema migrations must be safe to run multiple times:
- `CREATE TABLE IF NOT EXISTS`
- `CREATE INDEX IF NOT EXISTS` (or safe patterns)
- schema-qualified function defaults where required
- consistent extension setup

Your existing progress notes already mention hardening around UUID defaults and idempotency; this plan formalizes it as mandatory.

---

## 6) Concurrency controls (prevent overload)

### 6.1 Migration concurrency
Set an explicit maximum number of tenant migrations running concurrently:
- initial recommendation: 2–5 concurrent tenant migrations
- increase only after measuring DB capacity

Implementation shape (conceptual):
- a global semaphore/token bucket in the job runner
- or Oban queue concurrency with a dedicated queue (e.g., `tenant_migrations`) + limited concurrency

### 6.2 Per-tenant job concurrency
Even after migrations, you must prevent one tenant from dominating execution:
- Use separate Oban queues or per-tenant concurrency keys for:
  - executions
  - integration polling
  - webhook processing
  - directive runners (install/upgrade)

Baseline recommendation:
- enforce per-tenant concurrency caps for all job categories that can spike
- treat “premium tier” as a higher cap (see §9)

### 6.3 Connection pooling strategy
You do not want a pool per tenant. You want:
- a shared pool sized to your DB capacity
- strict job concurrency and request concurrency to stay below pool size
- predictable patterns that avoid long-held connections

Operational rule:
- reduce concurrency in jobs before increasing DB max connections.

---

## 7) Tenant lifecycle management (reconciliation and repair)

### 7.1 Tenant provisioning workflow
Org creation should be treated as a multi-step workflow:
1) create org record (public schema)
2) create tenant schema
3) apply tenant baseline (extensions/functions)
4) apply tenant migrations
5) mark org as “ready”

If any step fails:
- mark org as not-ready
- emit signals + logs (Phase 2B signals/directives)
- attempt cleanup if safe (drop schema if org creation should rollback)

### 7.2 Reconciliation job
Run a periodic reconciliation job (e.g., daily) that checks:
- orgs missing schemas
- schemas missing orgs (orphan schemas)
- tenant schemas behind current tenant migration release
- tenant extension/function drift

For each issue, it should:
- produce a repair directive (audited) or a repair job
- never silently destroy data in production without an explicit directive

### 7.3 Orphan schema policy
Orphan schemas can exist due to partial failures. Policy:
- in dev/staging: safe auto-clean (optionally)
- in prod: require an explicit admin directive to drop a schema, plus a delay window

---

## 8) Observability for tenancy operations

### 8.1 Minimum telemetry/log fields for every tenant job
Every tenant-scoped job should log:
- tenant schema
- org id/slug (if available)
- job id
- correlation_id / causation_id
- operation type (`tenant_migration`, `package_install`, etc.)

### 8.2 Admin UI needs
You should add an admin “Tenancy Ops” section (later) showing:
- tenants by schema version
- migration status per tenant
- last migration error and replay action
- schema repair actions (directive-driven)

---

## 9) Tiering strategy (premium vs standard)
Tenant scaling is not just technical — it’s product tiering.

### 9.1 Tenant classes
Define tenant classes early (even if not billed yet):
- `standard` (SMB)
- `premium` (higher concurrency, longer retention, priority migrations)
- `enterprise` (schema-per-tenant always; custom compliance options)

### 9.2 Operational differences per class
- Migration priority: premium/enterprise first (or last, depending on risk appetite)
- Job concurrency caps: higher for premium/enterprise
- Retention: signals might be extended for enterprise later (but today it’s 30 days globally)

---

## 10) Decision point: when schema-per-tenant stops being enough
Schema-per-tenant can scale surprisingly far if managed well, but you must define triggers for evaluating alternatives.

### 10.1 Trigger thresholds (recommended)
Start evaluating options when any of these become true:
- > 500 tenants and tenant migration wall-clock exceeds your deploy window repeatedly
- tenant migrations frequently fail due to lock contention or DDL incompatibilities
- DB maintenance (vacuum/analyze) becomes unpredictable
- you cannot keep connection usage stable under combined web + job load
- operational overhead (support incidents tied to tenancy) is rising

### 10.2 Options at scale
When triggers hit, you have three primary options:

#### Option A: Keep schema-per-tenant, add database sharding
- Group tenants across multiple Postgres instances (or clusters).
- Public schema remains centralized (or replicated carefully).
- Tenants are assigned to shards.

Pros:
- preserves isolation and restore story
- continues your current model

Cons:
- operational complexity increases (routing, shard assignment, backups)

#### Option B: Hybrid tenancy (recommended future path)
- Enterprise: schema-per-tenant (strong isolation)
- SMB: shared schema + Row Level Security (RLS) and `tenant_id` columns

Pros:
- avoids N-schema migration fanout for SMB
- improves operational simplicity at high tenant counts
- preserves enterprise isolation where it matters

Cons:
- requires dual-path data access and migration plan
- must be done carefully to avoid security regressions

#### Option C: Shared schema for all tenants (RLS)
- All tenants in a shared schema.
- Enforce isolation via policies and RLS.

Pros:
- simplest migrations
- easiest global analytics

Cons:
- riskier to get correct
- changes your compliance posture
- “export/restore per tenant” needs more work

---

## 11) Migration path to hybrid tenancy (if needed)
If you adopt Option B later, do it incrementally:

### 11.1 Start by adding `tenant_id` columns everywhere (even in schema-per-tenant)
Even if redundant, having a logical tenant id in records makes:
- future migration easier
- analytics easier
- potential cross-schema tooling possible

You can introduce this gradually for new tables first, then backfill.

### 11.2 Introduce a shared-schema “SMB v2” domain
Create a parallel set of resources or tables for SMB tenants:
- `smb_agents`, `smb_executions`, etc.
with `tenant_id` columns and RLS policies.

### 11.3 Dual-read migration strategy (later)
For tenants migrating from schema-per-tenant → shared-schema:
- export tenant data
- import into shared schema
- verify counts and integrity
- flip tenant routing
- keep old schema for a retention window, then drop via directive

This must be directive-driven and auditable.

---

## 12) Concrete backlog (what to build and when)

### Phase 2B aligned (near-term)
1) `tenant_migration_runs` (public) + minimal UI visibility
2) tenant migration job per schema with status tracking
3) feature gating based on tenant migration readiness
4) reconciliation job for drift/orphans

### Next (as integrations scale)
5) per-tenant job concurrency caps (executions, webhooks, polling, installs)
6) integration credential encryption strategy (separate doc; required before shipping real OAuth packages)
7) shard planning doc (even if not implemented)

---

## 13) Summary
Schema-per-tenant is the right choice today for FleetPrompt’s stage and trust posture, but it only remains viable if:
- tenant migrations become a first-class, observable workflow
- concurrency and connection usage are tightly controlled
- reconciliation and repair are built in
- you define clear thresholds for when to consider hybrid tenancy

This plan gives you a concrete path to operate schema-per-tenant safely now and migrate later without a rewrite.