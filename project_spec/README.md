# FleetPrompt — Reimplementation Spec (Portfolio-integrated)

FleetPrompt is being reimplemented. FleetPrompt legacy now lives in `fleetprompt.com/old_scrap/` and should be treated as **engineering reference**, not the target architecture.

In the portfolio architecture, FleetPrompt runs as an **OpenSentience Agent** focused on:

- Skill discovery + validation (`.fleetprompt/skills/`)
- Workflow definitions + execution (`.fleetprompt/workflows/`)
- Exposing skills/workflows as tools to OpenSentience Core

Canonical portfolio context:
- `opensentience.org/project_spec/portfolio-integration.md`

## Scope clarification: FleetPrompt Engine vs FleetPrompt Marketplace

This spec set (`fleetprompt.com/project_spec/`) describes the **FleetPrompt Engine**: an OpenSentience-managed agent that discovers/validates `.fleetprompt/` resources and executes skills/workflows locally via OpenSentience Core tool routing.

The **FleetPrompt Marketplace** (commercial) is a separate product from the FleetPrompt Engine reimplementation plan. Marketplace-level specs live here:
- `MARKETPLACE_COMMERCIAL.md` (accounts, Stripe Connect payouts, listings, entitlements, artifacts/download delivery, Ash+Phoenix+Inertia+Svelte stack)

The marketplace must remain compatible with OpenSentience Core’s trust boundaries and governance docs:
- `opensentience.org/project_spec/TRUST_AND_REGISTRY.md` (registry/provenance/verification posture, including paid-updates entitlements)
- `opensentience.org/project_spec/agent_marketplace.md` (install/build/enable/run lifecycle and safe-by-default constraints)

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

- Building the **FleetPrompt Marketplace** (commercial web app). This spec set focuses on the FleetPrompt Engine (agent runtime) only. See `MARKETPLACE_COMMERCIAL.md` for the marketplace plan/spec.
- Rebuilding FleetPrompt Engine as a multi-tenant SaaS.
- Reusing Phoenix/Ash multitenancy (`org_<slug>` schemas) inside the Engine. That model was correct for SaaS, but it is not required for a local agent MVP.

## Open questions (explicit)

- Should workflow definitions be YAML-only first, or support Elixir scripts early?
- Where should executions be stored: `~/.opensentience/` (core-owned) or `~/.fleetprompt/` (agent-owned)?
- Do you want FleetPrompt to maintain its own local DB, or rely on OpenSentience Core storage + APIs?
