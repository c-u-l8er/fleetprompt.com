# FleetPrompt — Agent Interface

FleetPrompt is the open marketplace for production-ready AI agents in the [&] Protocol ecosystem.

## For agents

FleetPrompt provides discovery and installation services for agents:

### Discovery
- Search agents by capability (`&memory.graph`, `&time.anomaly`, etc.)
- Filter by trust score, domain, runtime compatibility
- Browse agent manifests with declared permissions and dependencies

### Installation
- One-click deploy agent manifests to OpenSentience runtime
- Automatic permission review on install
- MCP server dependencies resolved automatically

### Publishing
- Push tested agents with SPEC.md manifests from Agentelic
- Trust score computed from: test coverage, usage metrics, audit history
- Semantic versioning enforced

## Agent Manifest Format

Every published agent includes:
- Name, version, author
- Capability declarations ([&] primitives used)
- Permission requirements (filesystem, network, tool invocation, graph access)
- MCP server dependencies
- SpecPrompt spec reference for full traceability
- Trust score

## Pipeline Position

```
SpecPrompt (define) → Agentelic (build) → FleetPrompt (distribute) → OpenSentience (run)
```

## Status

Spec complete. Implementation pending. See `docs/spec/README.md`.
