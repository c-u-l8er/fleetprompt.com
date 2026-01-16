# Current status and code map (as-built)

This document summarizes FleetPrompt’s current implementation state as an engineering asset: what exists, what is proven, and where the extension seams are.

For an ops-style status snapshot, see [`project_progress/STATUS.md`](project_progress/STATUS.md:1).

## Architecture snapshot

### UI
- **Inertia + Svelte** is canonical.
- `/chat` is an Inertia page backed by an SSE endpoint.

Key files:
- Router: [`FleetPromptWeb.Router`](backend/lib/fleet_prompt_web/router.ex:1)
- Chat UI: [`frontend/src/pages/Chat.svelte`](frontend/src/pages/Chat.svelte:1)
- Chat SSE endpoint: [`FleetPromptWeb.ChatController.send_message/2`](backend/lib/fleet_prompt_web/controllers/chat_controller.ex:62)

### Backend
- Phoenix + Ash + Oban.
- Tenant isolation: schema-per-tenant (`org_<slug>`) via Ash multitenancy.

## What is implemented (not speculative)

### 1) Signals (Phase 2B foundation)
- Tenant-scoped persisted signals in `org_<slug>.signals`.
- Idempotency via `dedupe_key`.
- Optional durable fanout (Oban) when the worker exists.

Key entrypoint: [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55).

### 2) Directives (Phase 2B foundation)
- Tenant-scoped persisted directives in `org_<slug>.directives`.
- Lifecycle: `requested → running → succeeded|failed|canceled`.
- Runner enforces guardrails: terminal-state discard, scheduled snooze, explicit rerun requirement.

Key modules:
- Directive resource: [`FleetPrompt.Directives.Directive`](backend/lib/fleet_prompt/directives/directive.ex:1)
- Runner: [`FleetPrompt.Jobs.DirectiveRunner`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1)

### 3) Package installs are directive-driven
- Marketplace install creates a tenant `Installation` and a `package.install` directive, then enqueues the runner.
- Runner enqueues the package installer.

This aligns to the Phase 2B plan in [`project_plan/phase_2b_signals_and_directives.md`](project_plan/phase_2b_signals_and_directives.md:1).

### 4) Forums lighthouse slice is real and auditable
- Tenant-scoped forum resources:
  - [`FleetPrompt.Forums.Category`](backend/lib/fleet_prompt/forums/category.ex:1)
  - [`FleetPrompt.Forums.Thread`](backend/lib/fleet_prompt/forums/thread.ex:1)
  - [`FleetPrompt.Forums.Post`](backend/lib/fleet_prompt/forums/post.ex:2)
- Forums writes emit signals (via controller code) and moderation is directive-backed (runner supports `forum.*`).

### 5) Chat SSE transport + tool calling loop
- `/chat/message` streams LLM output (OpenRouter OpenAI-compatible SSE) when configured.
- Tool calling is supported with an in-process loop:
  - assistant text streamed
  - tool calls accumulated
  - tools executed
  - tool results fed back to the model

Key modules:
- Chat SSE + tool loop: [`FleetPromptWeb.ChatController`](backend/lib/fleet_prompt_web/controllers/chat_controller.ex:1)
- LLM facade: [`FleetPrompt.LLM`](backend/lib/fleet_prompt/llm.ex:1)
- Tool surface: [`FleetPrompt.AI.Tools`](backend/lib/fleet_prompt/ai/tools.ex:1)

## Known gaps (important for future agent/skill/workflow design)

### A) Tool calls currently bypass the directive-first stance
Tools like [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105) perform direct writes (create category/thread/post) and return a string.

This is great for proving the mechanics, but it is *not yet* aligned with the stronger platform stance:
- side effects → directives
- facts → signals

Design implication for future work:
- treat current tool set as **prototype tools**
- migrate tool calls that mutate tenant state to **create directives** and let [`FleetPrompt.Jobs.DirectiveRunner`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1) perform the mutation

### B) Chat does not persist conversations/messages yet
The Chat controller explicitly notes no persistence in [`FleetPromptWeb.ChatController`](backend/lib/fleet_prompt_web/controllers/chat_controller.ex:14).

### C) Authorization/policies are intentionally light
Route-level auth exists; resource-level policies are not yet the long-term model.

### D) “Skill” and “Workflow” are not yet first-class platform primitives
The repo has placeholders and early work, but the docs below treat Skills/Workflows as *design targets* consistent with the Signals/Directives model.

## The extension seams (where to build next)

1. **Add a tool** (for Chat): extend [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10) + [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105).
2. **Add a new directive type**: extend the dispatch table in [`FleetPrompt.Jobs.DirectiveRunner.execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197).
3. **Emit a new domain signal**: call [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55) at the system boundary.
4. **Add a new package install behavior**: extend package installer logic and keep it deterministic/idempotent.

## Recommended hardening milestones (doc-driven)

- Convert mutating chat tools to directive requests.
- Standardize “subject” typing and dedupe keys for all important signals.
- Add an operator-friendly audit timeline viewer as a first-class UI pattern.

These are expanded in:
- [`project_guide/02_SIGNALS_AND_DIRECTIVES.md`](project_guide/02_SIGNALS_AND_DIRECTIVES.md:1)
- [`project_guide/04_CHAT_TOOL_CALLING.md`](project_guide/04_CHAT_TOOL_CALLING.md:1)
