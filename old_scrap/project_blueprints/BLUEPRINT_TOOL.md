# Blueprint: Tool (Chat tool-calling)

This blueprint describes how to design a FleetPrompt tool so it is:
- safe (tenant-scoped, role-aware)
- audit-friendly (signals/directives)
- compatible with the current chat tool loop

Current implementation anchors:
- Tool registry: [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10)
- Tool execution: [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105)
- Tool loop: [`FleetPromptWeb.ChatController.do_run_tool_loop/6`](backend/lib/fleet_prompt_web/controllers/chat_controller.ex:191)

## 1) Tool contract

### 1.1 Required fields (tool definition)

A tool definition (OpenAI-compatible) should include:
- `name`
- `description`
- `parameters` (JSON schema)

### 1.2 Required execution signature

The tool executor is called with:
- `tool_name`
- `arguments` (map)
- `tenant` (string like `org_demo`)
- `actor_user_id` (uuid string)

See [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105).

## 2) Tool types (recommended taxonomy)

### 2.1 Read-only tools (safe by default)

Characteristics:
- perform reads only
- return normalized structured data
- still emit signals optionally at high-value boundaries (later)

Examples:
- list forum categories
- search packages

### 2.2 Mutating tools (must evolve to directive-backed)

Rule:
- tools should **not** directly mutate tenant state long-term.

Recommended pattern:
- tool requests a directive (persisted intent)
- directive runner performs the write
- tool returns `{directive_id, status, preview}`

Reference runner: [`FleetPrompt.Jobs.DirectiveRunner.perform/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:37).

## 3) Inputs and validation

### 3.1 Argument validation

- Validate required fields and types before doing any work.
- Reject unknown fields where possible.

### 3.2 Tenant enforcement

- Require `tenant` to be present and valid.
- Never accept a tenant override inside tool `arguments`.

## 4) Outputs

Tools should return JSON-encodable structures.

Recommended response shape:

```json
{
  "ok": true,
  "type": "forum.thread.create.requested",
  "result": {
    "directive_id": "...",
    "subject": {"type": "forum.thread", "id": "..."}
  },
  "human_readable": "Requested creation of thread …"
}
```

Avoid returning raw database structs or internal exceptions.

## 5) Observability

Minimum:
- include correlation ids where available (chat request id)
- emit a signal when the directive is requested (or let directive lifecycle signals cover it)

Signal emitter: [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55).

## 6) Example: directive-backed forum post creation tool (target state)

### 6.1 Tool definition (conceptual)

- name: `forum_post_create`
- args:
  - `thread_id` (uuid)
  - `content` (string)

### 6.2 Execution flow

1. Validate args
2. Build idempotency key:
   - `forum.post.create:{tenant}:{thread_id}:{client_request_id}`
3. Create directive `forum.post.create` with payload
4. Enqueue directive runner
5. Return directive id

Implementation location (when you add it):
- tool request code in [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105)
- directive handler in [`FleetPrompt.Jobs.DirectiveRunner.execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197)

## 7) Checklist for adding a new tool

- [ ] It is safe under tenant isolation.
- [ ] It does not accept tenant overrides.
- [ ] If mutating, it requests a directive (not a direct write).
- [ ] It never stores secrets in signals/logs.
- [ ] It returns JSON-safe data.
- [ ] It has a stable idempotency strategy if it can be retried.
