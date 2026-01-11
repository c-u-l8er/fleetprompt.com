# Glossary and naming conventions

This is a short shared vocabulary and naming guide to keep future agent/skill/workflow work consistent.

## Glossary

### Tenant
An organization’s isolated data scope.

- Postgres schema-per-tenant: `org_<slug>`
- Tenant selection in requests: [`FleetPromptWeb.Plugs.FetchOrgContext`](backend/lib/fleet_prompt_web/plugs/fetch_org_context.ex:1)

### Package (registry)
A global marketplace record (public schema) describing installable capabilities.

- [`FleetPrompt.Packages.Package`](backend/lib/fleet_prompt/packages/package.ex:1)

### Installation
A tenant-scoped lifecycle record for a package.

- [`FleetPrompt.Packages.Installation`](backend/lib/fleet_prompt/packages/installation.ex:1)

### Signal
An immutable tenant-scoped fact: what happened.

- Resource: [`FleetPrompt.Signals.Signal`](backend/lib/fleet_prompt/signals/signal.ex:1)
- Emission: [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55)

### Directive
A tenant-scoped command (controlled intent): what should happen.

- Resource: [`FleetPrompt.Directives.Directive`](backend/lib/fleet_prompt/directives/directive.ex:1)
- Runner: [`FleetPrompt.Jobs.DirectiveRunner.perform/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:37)

### Handler
A module that consumes signals (fanout) or executes directives (runner dispatch).

- Signal fanout: [`FleetPrompt.Jobs.SignalFanout`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:1)
- Directive dispatch: [`FleetPrompt.Jobs.DirectiveRunner.execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197)

### Tool
A typed function exposed to the LLM via OpenAI-style tool calling.

- Tool registry: [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10)
- Tool execution: [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105)

### Actor
The entity responsible for an action.

- common actor types: `user`, `agent`, `system`
- stored on signals as `actor_type` + `actor_id`: [`FleetPrompt.Signals.Signal`](backend/lib/fleet_prompt/signals/signal.ex:87)

### Subject
The entity that an event or directive is about.

- stored on signals as `subject_type` + `subject_id`: [`FleetPrompt.Signals.Signal`](backend/lib/fleet_prompt/signals/signal.ex:98)
- can be embedded in directive payload and later derived by the runner: [`lifecycle_subject/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1000)

### Correlation id / causation id
Tracing fields:
- correlation groups related work
- causation links to the triggering event

Implemented on signals: [`FleetPrompt.Signals.Signal`](backend/lib/fleet_prompt/signals/signal.ex:76)

### Dedupe key
A stable key that prevents duplicate signals.

- stored on signals: [`dedupe_key`](backend/lib/fleet_prompt/signals/signal.ex:43)

### Idempotency key
A stable key that prevents duplicate directives.

- stored on directives: [`idempotency_key`](backend/lib/fleet_prompt/directives/directive.ex:45)

## Naming conventions

### Signal names

Format:
- lowercase, dot-delimited namespaces
- no versions in name (versions go in payload)

Validation is enforced at create time:
- [`Signal.emit` validation](backend/lib/fleet_prompt/signals/signal.ex:152)

Examples:
- `forum.thread.created`
- `package.install.processed`
- `directive.succeeded`

### Directive names

Format:
- lowercase, dot-delimited “commands”

Validation:
- [`Directive.request` validation](backend/lib/fleet_prompt/directives/directive.ex:177)

Examples:
- `package.install`
- `forum.thread.lock`

### Tool names

Format:
- OpenAI tool function names are snake_case strings.

Examples (current):
- `create_forum_category` in [`Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10)
- `list_forum_threads` in [`Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10)

### Subject types

Recommended taxonomy:
- `forum.thread`
- `forum.post`
- `forum.category`
- `package.installation`
- `package`

Keep these consistent across signals, directives, and UI audit timelines.

## Practical rule

If you’re unsure what to call something:
- copy the patterns already used in forums + package install flows
- prefer consistent naming over novelty
