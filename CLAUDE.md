# FleetPrompt — The Open Agent Marketplace

Discover, publish, and install production-ready AI agents. Built on trust scores, versioned manifests, and one-click deployment.

## Source-of-truth spec

- `project_spec/README.md` — FleetPrompt technical specification

## Role in [&] Ecosystem

FleetPrompt is the **distribution layer** — it does not provide [&] primitives but consumes all of them. It is the marketplace where spec-driven agents are published, discovered, and deployed.

## Pipeline

```
SpecPrompt (spec) → Agentelic (build) → FleetPrompt (publish/discover) → OpenSentience (deploy)
```

Every agent on FleetPrompt:
1. Is built against a SpecPrompt specification
2. Tested in Agentelic
3. Published with a versioned manifest declaring capabilities, permissions, and dependencies
4. Trust-scored from tests, usage, and audits
5. One-click installable to OpenSentience runtime

## Key features

- Agent manifests with semantic versioning and declared permissions
- Trust scoring (test coverage, usage history, audit results)
- Search by capability, trust score, domain, or compatible runtime
- MCP dependency declaration
- Fork-and-customize workflow

## Status

This is a spec + marketing site. No implementation code yet. Implementation will be a web application (stack TBD).
