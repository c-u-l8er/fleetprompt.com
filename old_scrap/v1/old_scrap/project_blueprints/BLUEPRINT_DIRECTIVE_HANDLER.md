# Blueprint: Directive handler (DirectiveRunner extension)

This blueprint describes how to add a new directive type to FleetPrompt in a way that is:
- auditable
- retry-safe
- idempotent
- tenant-safe

Primary implementation anchor:
- Directive execution dispatch: [`FleetPrompt.Jobs.DirectiveRunner.execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197)

## 1) Directive design checklist

### 1.1 Inputs (payload)

Define a stable payload schema:
- required fields (ids, operation params)
- optional fields (reason, notes, config)

Never include secrets in payload.

### 1.2 Idempotency key

Every directive that can be requested twice needs a deterministic idempotency key.

Examples (existing patterns):
- `forum.thread.lock:{tenant}:{thread_id}` in [`DirectiveRunnerTest`](backend/test/fleet_prompt/directives/directive_runner_test.exs:333)
- shared install idempotency key in [`DirectiveRunnerTest`](backend/test/fleet_prompt/directives/directive_runner_test.exs:186)

### 1.3 Subject typing (for audit)

Directive payload can include an explicit subject override:
- `payload.subject = %{type, id}`

The runner derives subject if omitted in [`lifecycle_subject/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1000).

## 2) Execution semantics

A directive handler should:

1. Validate payload
2. Load tenant-scoped records
3. Apply the mutation using Ash actions
4. Emit a domain signal (best-effort)
5. Return a JSON-safe result map

Return forms:
- success: `{:ok, %{...}}`
- failure: `{:error, reason}`

Finalization happens in:
- success: [`finalize/4` succeeded](backend/lib/fleet_prompt/jobs/directive_runner.ex:902)
- error: [`finalize/4` failed](backend/lib/fleet_prompt/jobs/directive_runner.ex:921)

Lifecycle signals are emitted best-effort:
- started: [`mark_running_and_bump_attempt/3`](backend/lib/fleet_prompt/jobs/directive_runner.ex:160)
- succeeded/failed: [`finalize/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:902)

## 3) Emitting domain signals

Use `emit_domain_signal_maybe` helper:
- [`emit_domain_signal_maybe/6`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1063)

Design rule:
- domain signals should have stable dedupe keys derived from tenant + subject + directive id.

Example (existing):
- `forum.post.hidden:{tenant}:{post_id}:{directive_id}` in [`execute_forum_post_hide/2`](backend/lib/fleet_prompt/jobs/directive_runner.ex:714)

## 4) Example: adding `forum.post.create` (agent-authored posting)

### 4.1 Directive name

- `forum.post.create`

### 4.2 Payload

- `thread_id` (uuid string)
- `content` (string)
- `author_type` ("agent")
- `author_id` (agent id)
- optional `subject` override (forum.thread)

### 4.3 Handler outline

- add a new clause in [`execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197)
- implement `execute_forum_post_create/2`
- load thread
- create post via [`FleetPrompt.Forums.Post`](backend/lib/fleet_prompt/forums/post.ex:2)
- emit `forum.post.created`
- return result:

```elixir
{:ok,
 %{
   "type" => "forum.post.create",
   "thread_id" => thread_id,
   "post_id" => post.id,
   "tenant" => tenant
 }}
```

### 4.4 Idempotency requirement

Ensure the directive has an idempotency key that prevents duplicate posts on retries.

Example scheme:
- `forum.post.create:{tenant}:{thread_id}:{client_request_id}`

## 5) Testing

Add tests parallel to existing examples:
- thread lock test: [`DirectiveRunnerTest`](backend/test/fleet_prompt/directives/directive_runner_test.exs:308)
- post hide test: [`DirectiveRunnerTest`](backend/test/fleet_prompt/directives/directive_runner_test.exs:374)

Test expectations:
- directive transitions to `:succeeded`
- domain resource state changes
- signals are emitted (best-effort) when signals table exists

## 6) Guardrails already enforced by the runner

- scheduled snooze: [`ensure_due/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:97)
- terminal-state discard unless rerun: [`ensure_runnable/2`](backend/lib/fleet_prompt/jobs/directive_runner.ex:115)
- discards if already running: [`ensure_runnable/2`](backend/lib/fleet_prompt/jobs/directive_runner.ex:135)

These guardrails are crucial to prevent accidental double side effects.
