# FleetPrompt — Reimplementation Spec (Portfolio-integrated)

FleetPrompt is being reimplemented. FleetPrompt legacy now lives in `fleetprompt.com/old_scrap/` and should be treated as **engineering reference**, not the target architecture.

In the portfolio architecture, FleetPrompt runs as an **OpenSentience Agent** focused on:

- Skill discovery + validation (`.fleetprompt/skills/`)
- Workflow definitions + execution (`.fleetprompt/workflows/`)
- Exposing skills/workflows as tools to OpenSentience Core

Canonical portfolio context:
- `opensentience.org/project_spec/portfolio-integration.md`

## Read this spec in order

1. `ARCHITECTURE.md` — component boundaries + responsibilities
2. `RESOURCE_SURFACES.md` — `.fleetprompt/` file formats and schemas
3. `INTERFACES.md` — the stable tool/signal/directive surface FleetPrompt exposes
4. `EXECUTION_MODEL.md` — runs, idempotency, cancellation, logs
5. `SIGNALS_DIRECTIVES_AUDIT.md` — how FleetPrompt stays auditable (FleetPrompt “hidden gems” preserved)
6. `SECURITY.md` — guardrails (prompt injection, secrets, drive-by actions)
7. `PERMISSIONS.md` — permissions model (manifest + per-skill scopes)
8. `MVP_PLAN.md` — implementation phases (reimplementation-first)
9. `TEST_PLAN.md` — what to test to avoid regressions
10. `LEGACY_LESSONS.md` — what we are explicitly carrying forward from `old_scrap/`

## Goals

1. **FleetPrompt runs as an OpenSentience Agent**
   - Installed/enabled/run by OpenSentience Core.

2. **Portfolio-first integration**
   - `.fleetprompt/` is the standard resource surface.
   - Skills/workflows can call into Graphonomous, Delegatic, and A2A through OpenSentience tool routing.

3. **Preserve the legacy “hidden gems” as requirements**
   - Signals vs Directives stance (facts vs intent)
   - Directive-backed side effects
   - Auditability + replayability
   - Tool calling loop patterns

## Non-goals (for reimplementation MVP)

- Rebuilding FleetPrompt as a multi-tenant SaaS.
- Reusing Phoenix/Ash multitenancy (`org_<slug>` schemas). That model was correct for SaaS, but it is not required for a local agent MVP.

## Open questions (explicit)

- Should workflow definitions be YAML-only first, or support Elixir scripts early?
- Where should executions be stored: `~/.opensentience/` (core-owned) or `~/.fleetprompt/` (agent-owned)?
- Do you want FleetPrompt to maintain its own local DB, or rely on OpenSentience Core storage + APIs?
