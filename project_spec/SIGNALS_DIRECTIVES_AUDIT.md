# Signals, Directives, and Audit (FleetPrompt)

FleetPrompt reimplementation must preserve the operability wins from legacy FleetPrompt.

## 1) Signals (facts)

FleetPrompt should emit signals for:

- skill discovered / workflow discovered
- execution started / progressed / finished
- validation succeeded / failed

Signals must be:

- immutable
- JSON-safe
- secret-free

## 2) Directives (intent)

FleetPrompt should request directives for:

- starting an execution (optional if Core initiates runs as directives)
- any side-effectful action (deploy, email, writes outside the project, integration calls)
- cancellation

## 3) Replay

Legacy FleetPrompt proved the usefulness of replaying facts through new handlers.

Reimplementation stance:

- executions and emitted signals should be replayable by correlation id
- handlers must be idempotent

## 4) Audit timeline UI pattern

OpenSentience Core UI should be able to merge into a single timeline:

- signals (facts)
- directives (intent)
- executions (work performed)

FleetPrompt should provide enough linking fields:

- `correlation_id`
- `causation_id` (optional)
- `subject_type` / `subject_id` (e.g. `fleetprompt.skill`, `fleetprompt.execution`)
