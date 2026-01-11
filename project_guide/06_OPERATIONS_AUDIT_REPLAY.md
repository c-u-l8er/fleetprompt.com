# Operations: audit trails, replay, and handler fanout

This guide explains how FleetPrompt’s operational story works today, based on the Phase 2B primitives already implemented.

Canonical spec:
- [`project_plan/phase_2b_signals_and_directives.md`](project_plan/phase_2b_signals_and_directives.md:1)

## Core idea

- **Signals** = immutable facts persisted in the tenant schema.
- **Directives** = auditable intent persisted in the tenant schema.
- **Oban jobs** = durable execution of fanout and directives.

These three together give FleetPrompt its core operability guarantees:
- you can answer what happened
- you can answer why it happened
- you can retry safely (if idempotency keys are correct)
- you can replay past facts through new handlers

## 1) Signal fanout (durable event processing)

### How fanout works

1. A signal is created (usually via [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55)).
2. Fanout is performed by an Oban worker: [`FleetPrompt.Jobs.SignalFanout.perform/1`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:51).
3. Fanout calls a list of configured handler modules in order.

### Handler configuration

Handlers are configured via application env (see docs in [`FleetPrompt.Jobs.SignalFanout`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:1)):

- `config :fleet_prompt, :signal_handlers, [SomeHandler, {OtherHandler, foo: :bar}]`

Handler function signatures supported:
- `handle_signal(signal, tenant, context)`
- `handle_signal(signal, context)`
- `handle_signal(signal)` (discouraged)

### Handler context map

Fanout passes a context map containing:
- `tenant`
- `signal_id`, `signal_name`
- `correlation_id`, `causation_id`
- Oban metadata (`job_id`, `attempt`, etc.)

See context construction: [`build_context/4`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:222).

### Testing example

A good reference for building handlers is the test:
- [`FleetPrompt.Signals.SignalBusTest`](backend/test/fleet_prompt/signals/signal_bus_test.exs:1)

It includes:
- a test handler receiving `context.handler_opts`
- a handler that returns `{:error, reason}` to force retries

## 2) Replay (re-enqueue fanout for persisted signals)

Replay is intentionally simple in v1. It does not attempt exact ordering or exactly-once delivery.

### Public functions

Implemented in [`FleetPrompt.Signals.Replay`](backend/lib/fleet_prompt/signals/replay.ex:1):

- `replay_recent(tenant, opts)`
- `replay_by_name(tenant, name, opts)`
- `replay_by_ids(tenant, ids, opts)`
- `replay_time_range(tenant, from_dt, to_dt, opts)`

Each method loads matching tenant-scoped signals and then enqueues a SignalFanout job per signal.

### Operational use cases

- After deploying a new handler, replay recent signals to backfill behavior.
- During debugging, replay a single signal id to reproduce downstream effects.
- During support, replay a narrow time range scoped to a specific incident.

### Safety rules

- Replay is only safe if handlers are idempotent.
- If replay may cause external side effects later (webhooks, email, etc.), handler logic must:
  - enforce its own idempotency keys
  - treat signals as facts, not commands

## 3) Directives + DirectiveRunner (durable commands)

Directives represent controlled intent. They are executed by the directive runner worker.

- Worker: [`FleetPrompt.Jobs.DirectiveRunner`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1)

The directive runner is responsible for:
- loading the directive record in the tenant schema
- transitioning lifecycle states
- performing the controlled mutation
- writing results/errors to the directive
- emitting lifecycle and domain signals as appropriate

The current runner supports:
- Package lifecycle commands (`package.install`, `package.uninstall`, etc.)
- Forums moderation commands (`forum.thread.lock`, `forum.post.hide`, etc.)

The definitive behavior examples are the tests:
- [`FleetPrompt.Directives.DirectiveRunnerTest`](backend/test/fleet_prompt/directives/directive_runner_test.exs:1)

## 4) The audit trail UI pattern

FleetPrompt treats “audit trail” as a first-class product surface.

The Forums thread view already demonstrates the pattern:
- load relevant signals for the domain entity
- load relevant directives that reference the domain entity
- merge into a timeline

Reference:
- thread action: [`ForumsController.thread/2`](backend/lib/fleet_prompt_web/controllers/forums_controller.ex:509)
- audit loads:
  - [`load_thread_audit_signals/3`](backend/lib/fleet_prompt_web/controllers/forums_controller.ex:1532)
  - [`load_thread_audit_directives/3`](backend/lib/fleet_prompt_web/controllers/forums_controller.ex:1561)

## 5) What to standardize next (recommended)

To make ops consistent as more packages/agents ship:

- Standardize `correlation_id` and `causation_id` generation at HTTP and directive boundaries.
- Expand signal coverage and adopt naming taxonomy from [`phase_2b_signals_and_directives.md`](project_plan/phase_2b_signals_and_directives.md:247).
- Add retention cleanup jobs for signals (per-tenant).
- Add an operator UI that can:
  - filter signals by subject
  - rerun a directive (explicitly)
  - replay a signal (admin only)
