# Blueprint: Agent (tenant-scoped)

This blueprint describes how to design an Agent inside FleetPrompt.

An Agent is a **tenant-scoped** resource that represents:
- a system prompt
- a model configuration
- execution limits and metrics

Current implementation anchor:
- [`FleetPrompt.Agents.Agent`](backend/lib/fleet_prompt/agents/agent.ex:1)

## 1) Agent responsibilities (FleetPrompt stance)

An Agent should not be treated as a generic autonomous actor.

Instead, an agent is a **component** in a larger system:
- it consumes structured inputs
- it may request tools
- it produces structured outputs
- it emits signals for audit

## 2) Data model (as-built)

Key fields in [`FleetPrompt.Agents.Agent`](backend/lib/fleet_prompt/agents/agent.ex:20):

- `name`, `description`
- `system_prompt`
- `config` (model/max_tokens/temperature)
- `state` state machine (`draft → deploying → active → paused → error`)
- execution limits (`max_concurrent_requests`, `timeout_seconds`)
- metrics (`total_executions`, `total_tokens_used`, `avg_latency_ms`)

## 3) Execution contract (target)

When the execution substrate is fully standardized (Phase 4), the contract should be:

Inputs:
- `input` (map)
- `context` (map including correlation_id, causation_id)

Outputs:
- `output` (map)
- logs (append-only)
- emitted signals

Reference execution direction:
- [`project_plan/phase_4_agent_execution.md`](project_plan/phase_4_agent_execution.md:1)

## 4) Tools and permissions

Agents should only call tools that are:
- explicitly allowed by the agent’s installed package(s) and tenant settings
- safe for the requesting actor role

Current tool surface is centralized in:
- [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10)

Recommended evolution:
- tools that mutate state should become directive-backed (see [`project_blueprints/BLUEPRINT_TOOL.md`](project_blueprints/BLUEPRINT_TOOL.md:1)).

## 5) Signals and directives

### 5.1 Signals (facts)

Agents should emit signals for:
- execution started/completed/failed
- tool call requested/performed
- domain outcomes (e.g. posted to forum)

Signal entrypoint:
- [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55)

### 5.2 Directives (intent)

Any side effect beyond pure computation should be executed as a directive:
- post as agent
- send an email
- moderate a forum thread

Directive execution is centralized in:
- [`FleetPrompt.Jobs.DirectiveRunner.execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197)

## 6) Blueprint: agent spec (recommended)

When defining an agent in a package, prefer a simple spec:

```json
{
  "agent": {
    "name": "Forum FAQ Agent",
    "version": "1.0.0",
    "description": "Detects duplicates and suggests answers",
    "system_prompt": "You are a forum assistant...",
    "config": {
      "model": "claude-sonnet-4",
      "max_tokens": 2048,
      "temperature": 0.2
    },
    "limits": {
      "max_concurrent_requests": 2,
      "timeout_seconds": 30
    },
    "capabilities": {
      "consumes_signals": ["forum.thread.created"],
      "may_request_directives": ["forum.post.create"],
      "allowed_tools": ["forum_categories_list", "forum_threads_search"]
    }
  }
}
```

## 7) Checklist for adding a new agent type

- [ ] Tenant-scoped.
- [ ] Clear purpose (one job).
- [ ] Safe defaults (low temperature, bounded tokens).
- [ ] No implicit side effects (use directives).
- [ ] Emits auditable signals.
- [ ] Has a deterministic idempotency strategy for publish actions.
