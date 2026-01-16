# Blueprint: Forum agent package (metadata-first)

This blueprint describes how to design an installable **Forum Agent** package that:
- provisions tenant records (agent configs, settings)
- subscribes to forum signals
- requests directives for any side effects

Canonical forum vision:
- [`project_plan/phase_6_agent_native_forum.md`](project_plan/phase_6_agent_native_forum.md:1)

Canonical primitives:
- Signals/Directives: [`project_plan/phase_2b_signals_and_directives.md`](project_plan/phase_2b_signals_and_directives.md:1)

## 0) Package stance

In v1, packages are **metadata-first**:
- do not ship arbitrary executable code
- the platform owns handler logic

Reference: [`project_plan/phase_2b_signals_and_directives.md`](project_plan/phase_2b_signals_and_directives.md:103)

Current registry resource:
- [`FleetPrompt.Packages.Package`](backend/lib/fleet_prompt/packages/package.ex:1)

Current tenant installation tracking:
- [`FleetPrompt.Packages.Installation`](backend/lib/fleet_prompt/packages/installation.ex:1)

## 1) What a forum agent package should declare

A forum agent package should declare, at minimum:

1. Provisioned assets
- one or more Agents (tenant-scoped) to run the work
- optional Skills (global references for now)
- optional Workflow definitions (later)

2. Signal subscriptions
- which `forum.*` signals it consumes

3. Allowed actions
- which directives it may request

4. Guardrails
- confidence thresholds
- rate limits
- cost caps

## 2) Recommended package manifest (conceptual)

```json
{
  "package": {
    "name": "Forum FAQ Agent",
    "slug": "forum_faq_agent",
    "version": "1.0.0",
    "category": "operations",
    "is_published": true,
    "includes": {
      "agents": [
        {
          "name": "Forum FAQ Agent",
          "description": "Detects duplicates and suggests prior threads",
          "system_prompt": "You are a forum FAQ assistant...",
          "config": {"model": "claude-sonnet-4", "max_tokens": 2048, "temperature": 0.2}
        }
      ],
      "skills": ["forum-duplicate-detection"],
      "tools": ["forum_threads_search"],
      "workflows": []
    },
    "capabilities": {
      "consumes_signals": ["forum.thread.created"],
      "may_request_directives": ["forum.post.create"],
      "safety": {
        "min_confidence": 0.7,
        "max_posts_per_hour": 10,
        "require_human_review_below_confidence": 0.7
      }
    }
  }
}
```

Note: the current `includes` field is already available in [`FleetPrompt.Packages.Package`](backend/lib/fleet_prompt/packages/package.ex:125). The `capabilities` block is a recommended addition as the platform hardens.

## 3) Event-driven behavior (how it should work)

### 3.1 Signal flow

- user creates thread → emit `forum.thread.created`
- signal fanout calls a handler
- handler decides if agent should respond
- handler requests directive(s)

Signal fanout:
- [`FleetPrompt.Jobs.SignalFanout.perform/1`](backend/lib/fleet_prompt/jobs/signal_fanout.ex:51)

### 3.2 Directive flow

The handler should request a directive for posting:
- `forum.post.create` (to be implemented)

Directive execution:
- [`FleetPrompt.Jobs.DirectiveRunner.execute/4`](backend/lib/fleet_prompt/jobs/directive_runner.ex:197)

## 4) Minimal “forum_faq_agent” blueprint (first package)

### Inputs
- signal: `forum.thread.created`
- data needed:
  - thread_id
  - title
  - first post content

### Steps

1. Handler receives `forum.thread.created` signal.
2. Search related threads (read-only tool or DB query).
3. If strong match, request directive `forum.post.create` with:
   - thread_id
   - suggested links
   - confidence score
4. Directive runner creates the post and emits `forum.post.created` and `forum.agent.responded` (future taxonomy).

## 5) Idempotency scheme

- Signal handler should be idempotent (can run multiple times).
- Posting directive must have a deterministic idempotency key.

Example:
- `forum.agent.reply_publish:{tenant}:{thread_id}:{signal_id}`

This prevents duplicate agent posts on retries and replays.

## 6) Operator UX requirements

A forum agent package is only trustworthy if operators can see:
- what happened (signals)
- why it happened (directives + execution logs)

The Forums lighthouse thread audit UI is the pattern to reuse:
- [`ForumsController.thread/2`](backend/lib/fleet_prompt_web/controllers/forums_controller.ex:509)

## 7) Security guardrails

- no secrets in signals/directives
- directive-backed side effects
- role gating for enabling/disabling agent packages

Reference: [`project_guide/07_SECURITY_GUARDRAILS.md`](project_guide/07_SECURITY_GUARDRAILS.md:1)
