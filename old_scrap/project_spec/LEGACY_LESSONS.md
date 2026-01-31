# Legacy FleetPrompt Lessons to Preserve

FleetPrompt legacy lives in `fleetprompt.com/old_scrap/`. It contains proven patterns that should inform the reimplementation.

## 1) Signals as immutable facts

Legacy implementation:

- `FleetPrompt.Signals.SignalBus` in `old_scrap/backend/lib/fleet_prompt/signals/signal_bus.ex`

Key properties worth preserving:

- single entrypoint for signal emission
- `dedupe_key` idempotency
- best-effort fanout enqueueing
- explicit “no secrets in payload/metadata” stance

## 2) Directives as controlled intent + durable execution

Legacy implementation:

- `FleetPrompt.Jobs.DirectiveRunner` in `old_scrap/backend/lib/fleet_prompt/jobs/directive_runner.ex`

Key properties worth preserving:

- lifecycle guards (scheduled snooze, terminal-state discard)
- explicit rerun requirement for terminal directives
- durable attempt tracking
- separation of request-time authorization vs run-time execution

## 3) Chat tool loop mechanics (streaming + tools)

Legacy implementation:

- `FleetPromptWeb.ChatController` in `old_scrap/backend/lib/fleet_prompt_web/controllers/chat_controller.ex`

Key properties worth preserving:

- SSE streaming contract
- tool-call accumulation and execution loop
- max-round safety bound

## 4) The “hidden gap” to fix

Legacy tools in `old_scrap/backend/lib/fleet_prompt/ai/tools.ex` directly mutated state.

Reimplementation requirement:

- mutating tools should create directives
- runners perform the mutation
- tools return `directive_id` + safe status
