FleetPrompt
========

FleetPrompt is **Layer 5 (Marketplace / Distribution)** in the WHS 6-layer ecosystem. This repository currently focuses on the **FleetPrompt marketplace spec** (not implementation code).

## Where to read the current spec (v1)

The **normative, implementation-ready v1 spec** lives here:

- `project_spec/spec_v1/README.md` — spec overview + reading order
- `project_spec/spec_v1/00_MASTER_SPEC.md` — master engineering spec (scope, flows, invariants, acceptance)
- `project_spec/spec_v1/10_API_CONTRACTS.md` — API shapes, normalized errors, pagination, idempotency, install handoff
- `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md` — data model + access control + invariants (Convex)
- `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` — threat model, UGC safety, token safety, confused deputy protections
- `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md` — test plan + release gates
- `project_spec/spec_v1/REALIGNMENT_PLAN.md` — spec-to-implementation checklist

ADRs (architecture decisions):
- `project_spec/spec_v1/adr/ADR-0001-references-not-copies.md`
- `project_spec/spec_v1/adr/ADR-0002-install-handoff-intents-tokens.md`

## Purpose (high level)

FleetPrompt v1 provides:
- **Marketplace discovery**: browse/search listings + safe listing pages
- **Publisher console**: create listings, publish releases (reference-first)
- **Install handoff**: create install intents + mint short-lived install tokens for server-to-server redemption by target systems

FleetPrompt v1 **does not**:
- execute agents (WHS owns runtime execution)
- execute workflows (Agentromatic owns orchestration/executions/logs)
- copy upstream telemetry/logs/transcripts (reference-first boundary)

## Notes on older materials

Anything under `old_scrap/` is **non-normative engineering reference** and should not be treated as the current target architecture. The source of truth is `project_spec/spec_v1/`.

