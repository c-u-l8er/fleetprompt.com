# FleetPrompt Execution Model

This document defines how skill/workflow runs behave.

## 1) Execution record (durable)

Every run produces an execution record with:

- `execution_id`
- `started_at`, `finished_at`
- `status`: `running | succeeded | failed | canceled`
- `actor` (human / agent) if available
- `inputs` (secret-free)
- `outputs` (redacted where necessary)
- `logs` (structured; secret-free)
- `correlation_id` (ties to upstream user request)

Storage location is an open decision:

- Core-owned (`~/.opensentience/`) is preferred if Core is the audit authority.
- Agent-owned (`~/.fleetprompt/`) is acceptable if Core can still query/merge audit.

## 2) Idempotency

- `fp_run_skill` and `fp_run_workflow` accept an optional `idempotency_key`.
- If a run with the same idempotency key is already completed, FleetPrompt should return the existing result.
- If a run with the same key is running, FleetPrompt should return a stable reference (no duplicate work).

## 3) Cancellation

- Long-running executions must be cancelable.
- Cancellation should be best-effort; the execution record must always reflect final status.

## 4) Streaming outputs

Where possible:

- stream intermediate log lines and partial results to OpenSentience Core
- allow Core UI to show progress

## 5) Side effects

A run may require side effects (filesystem writes, network requests, deployment actions).

Rule (carried from legacy FleetPrompt):

- side effects should be explicit directives
- tooling should not directly mutate high-impact state without the directive boundary
