# FleetPrompt Reimplementation — MVP Plan

This plan is scoped to a FleetPrompt agent that integrates cleanly into the OpenSentience portfolio.

## Phase 0 — Agent skeleton

- `opensentience.agent.json` for FleetPrompt
- implement the minimum protocol to connect to OpenSentience Core
- implement `fp_validate_project_resources`

## Phase 1 — Skill discovery + execution

- parse `.fleetprompt/config.toml`
- list/describe skills
- run a skill with:
  - input validation
  - idempotency key
  - structured logs

## Phase 2 — Workflow discovery + execution

- list/describe workflows
- execute workflows as sequences of skill runs
- add cancellation

## Phase 3 — Audit integration

- emit execution lifecycle signals
- request directives for side-effectful workflow steps
- expose `fp_list_executions` (optional) for UI

## Phase 4 — Portfolio integrations (opt-in)

- Graphonomous calls from workflows
- A2A triggers/subscriptions
- Delegatic mission integration
