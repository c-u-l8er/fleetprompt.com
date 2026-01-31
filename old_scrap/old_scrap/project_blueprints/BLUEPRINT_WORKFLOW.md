# Blueprint: Workflow (signal-driven orchestration)

This blueprint describes the intended Workflow design for FleetPrompt.

Current state:
- Workflow domain exists as a placeholder: [`FleetPrompt.Workflows`](backend/lib/fleet_prompt/workflows.ex:1)

Canonical design direction:
- [`project_plan/phase_4_agent_execution.md`](project_plan/phase_4_agent_execution.md:1)

## 1) What a workflow is (FleetPrompt stance)

A workflow is not “a background job with steps.”

A workflow is:
- a **tenant-scoped orchestration graph**
- that consumes signals
- requests directives
- runs executions
- emits signals at each meaningful boundary

## 2) Workflow primitives (recommended)

### 2.1 Workflow definition

Store a workflow definition as JSON (DAG):
- steps
- transitions
- conditions
- error handling policy

### 2.2 WorkflowRun

Every workflow run should be a durable record:
- status lifecycle
- input
- step results
- correlation_id and causation_id lineage

### 2.3 Step execution

Each step is an effect:
- run an agent execution
- call a deterministic function
- request a directive

## 3) Triggering model

Workflows should be triggered by signals.

Pattern:
1. Signal occurs (fact)
2. Signal handler decides whether to start/advance workflows
3. Handler requests directive `workflow.run.start` (auditable intent)
4. Directive runner creates a WorkflowRun and enqueues a workflow executor job

This keeps:
- triggers observable
- side effects controlled

## 4) Recommended workflow definition schema (v1)

```json
{
  "workflow": {
    "name": "Forum new-thread triage",
    "version": "1.0.0",
    "trigger": {
      "signal": "forum.thread.created"
    },
    "steps": [
      {
        "id": "summarize",
        "type": "agent",
        "agent_ref": {"slug": "forum_summary_agent"},
        "input": {"from_signal": true}
      },
      {
        "id": "post_summary",
        "type": "directive",
        "directive": "forum.post.create",
        "payload": {"thread_id": "${signal.subject.id}", "content": "${steps.summarize.output.summary}"}
      }
    ]
  }
}
```

## 5) Safety and idempotency

- every workflow run needs an idempotency key derived from the triggering signal
- every directive requested by the workflow needs its own idempotency key

## 6) Observability requirements

Each run should be traceable:
- correlation_id present on run
- causation_id pointing at triggering signal id
- step-level logs

Signals should include:
- `workflow.run.started`
- `workflow.step.completed`
- `workflow.run.completed` / `workflow.run.failed`

Signal bus: [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55)

## 7) Checklist for adding a workflow

- [ ] Trigger is a signal.
- [ ] Starts via directive (not hidden).
- [ ] Run is durable and tenant-scoped.
- [ ] Steps are idempotent and retry-safe.
- [ ] Emits signals for lifecycle + steps.
- [ ] Has an operator-friendly audit trail.
