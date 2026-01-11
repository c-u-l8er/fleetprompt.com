# FleetPrompt Blueprints

This directory contains reusable templates for designing **agents, skills, workflows, tools, and handler modules** in a way that aligns with FleetPrompt’s current architecture:

- Inertia + Svelte UI (not LiveView-first)
- schema-per-tenant data model (`org_<slug>`)
- Signals (facts) + Directives (intent)
- Oban jobs for durable execution

Start with the mental model:
- [`project_guide/00_MENTAL_MODEL.md`](project_guide/00_MENTAL_MODEL.md:1)

## Reading order

1. [`project_blueprints/BLUEPRINT_TOOL.md`](project_blueprints/BLUEPRINT_TOOL.md:1)
2. [`project_blueprints/BLUEPRINT_DIRECTIVE_HANDLER.md`](project_blueprints/BLUEPRINT_DIRECTIVE_HANDLER.md:1)
3. [`project_blueprints/BLUEPRINT_SIGNAL_HANDLER.md`](project_blueprints/BLUEPRINT_SIGNAL_HANDLER.md:1)
4. [`project_blueprints/BLUEPRINT_AGENT.md`](project_blueprints/BLUEPRINT_AGENT.md:1)
5. [`project_blueprints/BLUEPRINT_SKILL.md`](project_blueprints/BLUEPRINT_SKILL.md:1)
6. [`project_blueprints/BLUEPRINT_WORKFLOW.md`](project_blueprints/BLUEPRINT_WORKFLOW.md:1)
7. [`project_blueprints/BLUEPRINT_FORUM_AGENT_PACKAGE.md`](project_blueprints/BLUEPRINT_FORUM_AGENT_PACKAGE.md:1)

## Architectural anchors (as-built)

- Tool calling loop: [`FleetPromptWeb.ChatController.do_run_tool_loop/6`](backend/lib/fleet_prompt_web/controllers/chat_controller.ex:191)
- Tool registry/execution: [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10) and [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105)
- Signals: [`FleetPrompt.Signals.SignalBus.emit/4`](backend/lib/fleet_prompt/signals/signal_bus.ex:55)
- Signal fanout: [`FleetPrompt.Jobs.SignalFanout.perform/1`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:51)
- Directives: [`FleetPrompt.Directives.Directive`](backend/lib/fleet_prompt/directives/directive.ex:1)
- Directive execution: [`FleetPrompt.Jobs.DirectiveRunner.perform/1`](backend/lib/fleet_prompt/jobs/directive_runner.ex:37)
- Forums lighthouse resources: [`FleetPrompt.Forums.Category`](backend/lib/fleet_prompt/forums/category.ex:1), [`FleetPrompt.Forums.Thread`](backend/lib/fleet_prompt/forums/thread.ex:1), [`FleetPrompt.Forums.Post`](backend/lib/fleet_prompt/forums/post.ex:2)
