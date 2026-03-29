# FleetPrompt Documentation

> **The open marketplace where production-ready AI agents are published, discovered, and deployed in one click.**

Welcome to the documentation hub for **FleetPrompt** — the open agent marketplace
for the [&] Protocol ecosystem. FleetPrompt is the registry where production-ready
AI agents are published, discovered, and deployed. Every listed agent carries a
versioned manifest, a computed trust score, declared permissions, and a linked
SpecPrompt spec — making FleetPrompt the first marketplace where you know exactly
what an agent does before you install it.

---

## Why FleetPrompt?

57% of organizations now have AI agents in production (LangChain 2026). Yet there
are **zero open agent marketplaces**. Teams build agents in isolation, rediscover
the same patterns, and have no way to share, reuse, or monetize production-quality
work. Closed platforms (Salesforce AgentForce, OpenAI GPT Store) lock agents into
proprietary runtimes. Open frameworks (LangGraph, CrewAI) have no distribution
story at all.

FleetPrompt is the **distribution layer** of the [&] Protocol ecosystem:

```
SpecPrompt (Standards)    → defines agent behavior as versioned specs
    ↓
Agentelic (Engineering)   → builds, tests, deploys agents against specs
    ↓
OpenSentience (Runtime)   → governs, executes, observes agents locally
    ↓
Graphonomous (Memory)     → continual learning knowledge graphs
    ↓
FleetPrompt (Distribution) ← THIS  ·  Delegatic (Orchestration)
```

---

## Documentation Map


```{toctree}
:maxdepth: 1
:caption: Homepages

[&] Ampersand Box <https://ampersandboxdesign.com>
Graphonomous <https://graphonomous.com>
BendScript <https://bendscript.com>
WebHost.Systems <https://webhost.systems>
Agentelic <https://agentelic.com>
AgenTroMatic <https://agentromatic.com>
Delegatic <https://delegatic.com>
Deliberatic <https://deliberatic.com>
FleetPrompt <https://fleetprompt.com>
GeoFleetic <https://geofleetic.com>
OpenSentience <https://opensentience.org>
SpecPrompt <https://specprompt.com>
TickTickClock <https://ticktickclock.com>
```

```{toctree}
:maxdepth: 1
:caption: Root Docs

[&] Protocol Docs <https://docs.ampersandboxdesign.com>
Graphonomous Docs <https://docs.graphonomous.com>
BendScript Docs <https://docs.bendscript.com>
WebHost.Systems Docs <https://docs.webhost.systems>
Agentelic Docs <https://docs.agentelic.com>
AgenTroMatic Docs <https://docs.agentromatic.com>
Delegatic Docs <https://docs.delegatic.com>
Deliberatic Docs <https://docs.deliberatic.com>
FleetPrompt Docs <https://docs.fleetprompt.com>
GeoFleetic Docs <https://docs.geofleetic.com>
OpenSentience Docs <https://docs.opensentience.org>
SpecPrompt Docs <https://docs.specprompt.com>
TickTickClock Docs <https://docs.ticktickclock.com>
```

```{toctree}
:maxdepth: 2
:caption: FleetPrompt Docs

spec/README
```

---

## Design Principles

1. **Manifest-first** — Every agent defined by a machine-readable manifest. No opaque binaries.
2. **Trust by computation** — Trust scores derived from tests, audits, and usage — never self-reported.
3. **Permission transparency** — All permissions declared upfront, reviewed on install.
4. **Provenance chain** — Every version links to its SpecPrompt spec, build pipeline, and audit trail.
5. **One-click deploy** — Install means deploy to OpenSentience. No manual wiring.
6. **Open registry** — Public agents are free to publish and install. The marketplace is the commons.
7. **Fork-friendly** — Any public agent can be forked, customized, and republished.

---

## Architecture at a Glance

| Component | Role | OTP Pattern |
|-----------|------|-------------|
| **Registry Core** | Manifest storage, version control, search indexing, fork management | Ecto + ETS |
| **Trust Engine** | Async recompute of trust scores on new data | GenServer per agent |
| **Install Engine** | Manifest → OpenSentience deploy with permission review gate | Task pipeline |
| **Search** | Full-text + capability + trust-score search | ETS + PostgreSQL |
| **Dashboard** | Agent search, detail, trust scores, publisher profiles | Phoenix LiveView |

---

## The Trust Pipeline

Every agent on FleetPrompt gets a computed trust score based on:

- **Test coverage** — percentage of acceptance criteria with passing tests
- **Build provenance** — deterministic builds with hash-linked artifacts
- **Usage metrics** — install count, active deployments, error rates
- **Audit trail** — linked SpecPrompt spec, Agentelic build history
- **Community signals** — forks, reviews, reports

Trust scores are recomputed asynchronously whenever new data arrives.

---

## Project Links

- **Spec:** [Technical Specification](spec/README.md)
- **[&] Protocol ecosystem:** `AmpersandBoxDesign/`

---

*[&] Ampersand Box Design — fleetprompt.com*
