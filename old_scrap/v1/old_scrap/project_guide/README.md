# FleetPrompt Project Guide

This directory is the **living guidebook** for building and operating agentic systems inside FleetPrompt.

It is designed to complement (not replace) the phase roadmap in [`project_plan/PROJECT_PLAN.md`](project_plan/PROJECT_PLAN.md:1) by answering:
- how FleetPrompt works **as-built**
- how to extend it safely (agents, skills, workflows, packages)
- how to reason about auditability, idempotency, and replay (Signals + Directives)

## Reading order

1. [`project_guide/00_MENTAL_MODEL.md`](project_guide/00_MENTAL_MODEL.md:1)
2. [`project_guide/01_CURRENT_STATUS_AND_CODE_MAP.md`](project_guide/01_CURRENT_STATUS_AND_CODE_MAP.md:1)
3. [`project_guide/02_SIGNALS_AND_DIRECTIVES.md`](project_guide/02_SIGNALS_AND_DIRECTIVES.md:1)
4. [`project_guide/03_PACKAGES_AND_INSTALLATIONS.md`](project_guide/03_PACKAGES_AND_INSTALLATIONS.md:1)
5. [`project_guide/04_CHAT_TOOL_CALLING.md`](project_guide/04_CHAT_TOOL_CALLING.md:1)
6. [`project_guide/05_FORUMS_LIGHTHOUSE_LOOP.md`](project_guide/05_FORUMS_LIGHTHOUSE_LOOP.md:1)
7. [`project_guide/06_OPERATIONS_AUDIT_REPLAY.md`](project_guide/06_OPERATIONS_AUDIT_REPLAY.md:1)
8. [`project_guide/07_SECURITY_GUARDRAILS.md`](project_guide/07_SECURITY_GUARDRAILS.md:1)
9. [`project_guide/08_GLOSSARY_AND_NAMING.md`](project_guide/08_GLOSSARY_AND_NAMING.md:1)

## Companion blueprints

See reusable design templates in [`project_blueprints/README.md`](project_blueprints/README.md:1).

## Canonical code entrypoints (as-built)

- Chat + server-side tool loop: [`FleetPromptWeb.ChatController.send_message/2`](backend/lib/fleet_prompt_web/controllers/chat_controller.ex:62)
- Tool definitions + execution: [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10) and [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105)
- LLM streaming facade: [`FleetPrompt.LLM.stream_chat_completion/3`](backend/lib/fleet_prompt/llm.ex:135)
- Signals: [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55)
- Directives runner: [`FleetPrompt.Jobs.DirectiveRunner.perform/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:37)
- Forums core resources: [`FleetPrompt.Forums.Category`](backend/lib/fleet_prompt/forums/category.ex:1), [`FleetPrompt.Forums.Thread`](backend/lib/fleet_prompt/forums/thread.ex:1), [`FleetPrompt.Forums.Post`](backend/lib/fleet_prompt/forums/post.ex:2)

## Important stance (kept consistent across docs)

- UI architecture is **Inertia + Svelte** (not LiveView-first).
- Tenant isolation is **schema-per-tenant** via Ash multitenancy.
- **Signals** are immutable facts; **Directives** are controlled intent.
- Side effects should be **directive-backed** whenever they can be retried, audited, or cause external impact.
