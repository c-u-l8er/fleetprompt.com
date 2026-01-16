# FleetPrompt — Reimplementation Spec (Portfolio-integrated)

FleetPrompt is being reimplemented (FleetPrompt legacy is now “engineering reference”). The new FleetPrompt is an **OpenSentience Agent** focused on:

- Skill discovery and validation (`.fleetprompt/skills/`)
- Workflow definitions and execution (`.fleetprompt/workflows/`)
- Exposing skills/workflows as tools to OpenSentience Core

Canonical portfolio context: `opensentience.org/project_spec/portfolio-integration.md`.

## Goals

1. **FleetPrompt runs as an OS Agent**
   - Installed/enabled/run by OpenSentience Core.

2. **Portfolio-first integration**
   - `.fleetprompt/` becomes the standard resource surface.
   - Skills/workflows can reference Graphonomous, Delegatic, and A2A.

3. **Preserve the legacy “hidden gems”**
   - Signals/Directives stance (facts vs intent)
   - Directive-backed side effects
   - Auditability + replay
   - Tool calling loop patterns

## Non-goals (for reimplementation MVP)

- Rebuilding the entire FleetPrompt SaaS surface area.
- Phoenix/Ash multitenant schema-per-tenant (that was correct for SaaS; not required for local agent MVP).

## Required learned lessons from legacy FleetPrompt

### A) Signals vs Directives

Adopt the portfolio standard:

- facts are **signals**
- side effects are **directives**

### B) Tool calling must not bypass intent

In legacy FleetPrompt, some tools wrote directly to tenant state. For the reimplementation:

- mutating tools should create directives
- a runner performs the mutation
- the tool returns a directive id + safe status

### C) Secret-free durability

- no secrets in signals, directives, or logs
- secrets live in an encrypted credential store and are referenced by id

## Interfaces (as an OpenSentience Agent)

FleetPrompt exposes tools like:

- `fp_list_skills` / `fp_describe_skill`
- `fp_run_skill`
- `fp_list_workflows` / `fp_run_workflow`
- `fp_validate_project_resources` (validates `.fleetprompt/`)

All tool calls must be permission-checked.

## Data model (minimal MVP)

Persist as OpenSentience-managed state, or as FleetPrompt-managed local state:

- Skill catalog entries (from `.fleetprompt/config.toml` and `skills/`)
- Workflow catalog entries
- Executions (durable run records)

## Open questions

- Do you want workflow definitions to be YAML-only first, or support Elixir scripts early?
- Where should executions be stored: `~/.opensentience/` (core-owned) or `~/.fleetprompt/` (agent-owned)?
