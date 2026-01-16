# FleetPrompt Architecture (as an OpenSentience Agent)

## 1) Component boundaries

### OpenSentience Core owns

- agent lifecycle (install / enable / run / stop)
- permission approval and enforcement
- system-wide audit log
- tool routing between agents
- local-only admin UI (OpenSentience UI)

### FleetPrompt agent owns

- parsing/validating `.fleetprompt/` resources
- registering skills/workflows as callable tools
- executing skills/workflows (with cancellation + streaming where possible)
- emitting facts (signals) and requesting intent (directives) via Core APIs

## 2) FleetPrompt internal subsystems

1. **Resource Indexer**
   - reads `.fleetprompt/config.toml`
   - enumerates `skills/` and `workflows/`
   - validates schemas and file paths
   - produces a catalog of `Skill` and `Workflow` entries

2. **Tool Adapter**
   - maps each skill/workflow into an OpenAI-style tool definition
   - validates inputs against schema before execution

3. **Execution Engine**
   - runs skills/workflows with:
     - idempotency keys
     - durable execution records
     - cancellation
     - structured logs

4. **Audit Adapter**
   - emits signals for execution lifecycle
   - requests directives for side effects (or high-impact actions)

## 3) Key stance (from legacy FleetPrompt)

- **Signals** = immutable facts (what happened)
- **Directives** = controlled intent (what should happen)

Legacy FleetPrompt proved the operability value of this split.
For the reimplementation, it is a requirement: tools that cause side effects should not directly mutate state without an explicit directive boundary.

## 4) Integration points

- **Graphonomous**: skills can call `graph_search`/`graph_ingest` tools via Core
- **Delegatic**: workflows can be orchestrated as Delegatic missions (future)
- **A2A**: workflows can subscribe to/publish events (future)

## 5) Deployment model

- FleetPrompt runs locally as an OpenSentience-managed agent process.
- FleetPrompt should not open network listeners by default.
- If FleetPrompt exposes a UI later, it must be localhost-only and protected against drive-by actions.
