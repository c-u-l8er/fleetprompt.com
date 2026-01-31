# Blueprint: Signal handler (SignalFanout consumer)

This blueprint describes how to implement a Signal handler that consumes tenant-scoped Signals via durable fanout.

Primary anchors:
- Fanout worker: [`FleetPrompt.Jobs.SignalFanout.perform/1`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:51)
- Handler test example: [`FleetPrompt.Signals.SignalBusTest`](backend/test/fleet_prompt/signals/signal_bus_test.exs:1)

## 1) Handler interface

SignalFanout supports these handler function shapes:

- `handle_signal(signal, tenant, context)`
- `handle_signal(signal, context)`
- `handle_signal(signal)` (discouraged)

See invocation logic in [`invoke_handler/5`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:172).

## 2) Handler configuration

Handlers are configured in application env:

- `config :fleet_prompt, :signal_handlers, [MyHandler, {MyOtherHandler, opt: :x}]`

See [`configured_handlers/0`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:154).

## 3) Idempotency: assume at-least-once delivery

Oban retries mean your handler may run more than once.

Rules:
- do not assume “exactly once”
- if a handler triggers a side effect, it should do so via a directive with an idempotency key

## 4) Recommended pattern: signals trigger directives

### 4.1 Why

Signals are facts, not commands.

If you need to cause change:
- request a directive (auditable intent)
- let the directive runner perform the mutation

Reference:
- directive runner entry: [`FleetPrompt.Jobs.DirectiveRunner.perform/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:37)

### 4.2 Example: forum auto-summarizer (future)

- consume `forum.thread.created`
- check tenant settings and installed packages
- request directive `forum.thread.summarize` with idempotency key

## 5) Context usage

SignalFanout passes a context map built in:
- [`build_context/4`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:222)

Do not treat context as stable API; only rely on:
- `tenant`
- `signal_id`, `signal_name`
- correlation ids when present

## 6) Error handling

If your handler returns `{:error, reason}` then:
- the SignalFanout job fails and will be retried

See failure behavior:
- [`SignalBusTest` error handler](backend/test/fleet_prompt/signals/signal_bus_test.exs:24)

Practical rule:
- only return `{:error, _}` for transient failures
- for permanent “not applicable” states, return `:ok`

## 7) Safety rules

- never store secrets in signals
- never log raw external payloads without redaction
- never perform cross-tenant reads

Reference security posture:
- [`project_guide/07_SECURITY_GUARDRAILS.md`](project_guide/07_SECURITY_GUARDRAILS.md:1)
