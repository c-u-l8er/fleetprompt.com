# FleetPrompt — Phase 6: Agent‑Native Forum (“Killer App” Track)
File: `fleetprompt.com/project_plan/phase_6_agent_native_forum.md`  
Status: Spec (new)  
Last updated: 2026-01-07

## 0) Purpose

Phase 6 defines a **modern forum built for the agentic AI era** as a first-party FleetPrompt application (“killer app”) that:

- **dogfoods FleetPrompt’s primitives** (Packages, Installations, Signals, Directives, Executions, Workflows),
- creates a **distribution wedge** for FleetPrompt (communities invite communities),
- provides the clearest end-to-end demo of agent orchestration: “the forum that runs itself.”

This is explicitly **not** “a forum with a chatbot bolted on.” It is a discussion platform where **AI agents are first-class participants**, with **auditability and replay** built in.

---

## 1) Scope boundaries & non-goals

### 1.1 In-scope
- A forum app inside the FleetPrompt repo, aligned with:
  - Phoenix + Ash + Postgres (schema-per-tenant)
  - Inertia + Svelte UI (canonical UI stack)
  - Oban for async work
  - Phase 2B Signals + Directives as platform primitives
- An “agent-native” interaction model:
  - agents can be mentioned, respond, escalate, summarize, and moderate **via directives/executions**
  - user feedback loops to improve behavior and measure ROI

### 1.2 Non-goals (explicit)
- Competing on every Discourse/NodeBB feature in v1
- Building a generalized “social network” (DMs, Stories, etc.)
- Allowing arbitrary third-party code execution inside FleetPrompt (packages remain curated/metadata-first in early versions)
- Fully automated moderation that deletes content without human oversight (v1 should default to “flag + recommend + escalate”)

---

## 2) Strategic fit with existing project theory

This phase aligns with existing FleetPrompt theory:

- **Packages are the product surface area**: Forum Agents are installable packages (FAQ, Welcome, Summary, Moderation).
- **Signals are immutable facts**: Every thread/post/reaction is a signal; every agent action emits signals.
- **Directives are controlled intent**: Posting as an agent, flagging, tagging, closing, escalating are directives (auditable, idempotent).
- **Chat is a surface, not the engine**: Forum is another surface; it should drive executions/workflows through the same primitives.

The forum should also become the most convincing proof of:
- multi-tenant correctness,
- event replay,
- idempotency and safe retries,
- tool permission model.

---

## 3) Product concept (what the forum is)

### 3.1 System identity
**FleetPrompt Forum** is a multi-tenant forum where:
- humans discuss topics in categories/tags,
- agents participate as “accounts” (but clearly labeled),
- the system continuously produces **summaries, dedupe suggestions, routing, and safety enforcement**.

### 3.2 Primary user outcomes
1. **Questions get answered faster** (agent deflection + expert routing).
2. **Moderation load drops** (spam/toxicity/duplicate detection).
3. **Knowledge is retained** (thread summaries, decisions extracted).
4. **Search works better over time** (curated tags + agent-generated TL;DR + embeddings optional later).

---

## 4) Tenancy and deployment model

### 4.1 Tenancy stance
- Forum data is tenant-owned and stored in each `org_<slug>` schema.
- Global identity and registry remains in public schema (users, orgs, packages registry).
- Forum must not allow any client-provided tenant override (tenant derived from session/org selection; API keys later).

### 4.2 Deployment stance
- Forum runs as part of the FleetPrompt web app (same runtime, same deploy).
- A future split (“forum as separate app/service”) is out of scope until scale requires it.

---

## 5) Core features (MVP → Beta → v1)

### 5.1 MVP (“Dogfood + demo”)
- Categories (basic)
- Threads
- Posts (reply)
- Reactions (like/upvote)
- Basic moderation: flag a post
- Search (basic Postgres text search)
- Agent participation:
  - @mention agent in thread
  - agent can respond with citations (links to prior threads)
  - agent can escalate to humans (mentions or notifications)
- Observability:
  - thread/post signals emitted
  - agent actions are directives + executions + signals

### 5.2 Alpha (“Design partners”)
- User profiles, reputation (minimal)
- Solved threads (Q&A mode per category)
- Notifications (in-app; email later)
- Moderation queue UI
- Agent dashboard: resolution rate, escalation rate, feedback score

### 5.3 Beta (“Paying customers possible”)
- Theme/branding
- SSO/OAuth (align with Phase 5/enterprise later)
- SEO basics (server-rendered pages via Phoenix + Inertia)
- Rate limiting and spam controls hardened
- Agent marketplace integration: one-click install/configure forum agents

### 5.4 v1 (“Production maturity”)
- Data export tools
- Advanced analytics/insights
- Enterprise governance (audit logs, retention controls)
- Optional embedding/vector search upgrades (if justified)

---

## 6) Agent-native differentiation (must-haves)

These are the “killer app” requirements. If they’re missing, it’s just a forum.

### 6.1 Agents are first-class participants
- Agents have identities (clearly labeled as agents).
- Agent posts are distinguishable (`is_agent_generated`, confidence, model used optional).
- Users can:
  - @mention agents
  - rate agent responses (helpful / not helpful + reason)
  - request a summary or decision extraction

### 6.2 Agents never cause side effects without directives
Any action beyond “write a reply” must be directive-gated:
- closing/locking a thread
- moving categories/tags
- flagging/hiding content
- notifying groups/experts
- posting to external integrations (Mattermost/email)

### 6.3 Human escalation is a first-class path
Agents must be able to say “I’m not confident; paging humans,” and that action must be observable and measured.

### 6.4 Audit trail and replay is product, not backend plumbing
Admins must be able to view:
- which signals triggered which directives/executions,
- what the agent saw (sanitized context),
- why the agent chose an action (structured “decision record”),
- and replay a handler safely (idempotent).

---

## 7) Canonical signal taxonomy (forum)

Signals are tenant-scoped, persisted, immutable.

### 7.1 Thread and post signals
- `forum.category.created`
- `forum.thread.created`
- `forum.thread.viewed`
- `forum.thread.updated`
- `forum.thread.solved`
- `forum.thread.closed`
- `forum.post.created`
- `forum.post.edited`
- `forum.post.reacted`
- `forum.post.flagged`

### 7.2 Agent interaction signals
- `forum.agent.mentioned`
- `forum.agent.response.requested`
- `forum.agent.responded`
- `forum.agent.escalated`
- `forum.agent.summary.generated`
- `forum.agent.feedback.recorded`

### 7.3 Moderation signals
- `forum.moderation.flag.created`
- `forum.moderation.action.taken`
- `forum.spam.detected` (heuristic)
- `forum.toxicity.detected` (heuristic)

### 7.4 Required metadata on all forum signals
- `tenant` (schema name or org id reference; derived server-side)
- `actor_type`: `user | agent | system`
- `actor_id` (user id or agent id)
- `source`: `web | job | api`
- `correlation_id` and optional `causation_id`
- `dedupe_key` where relevant (e.g., view events, webhook-like sources)

---

## 8) Canonical directive taxonomy (forum)

Directives are tenant-scoped, persisted, auditable, idempotent.

### 8.1 Content directives
- `forum.post.create` (used for agent-authored posts; user posts can write directly but should still emit signals)
- `forum.post.suggest_edit` (non-destructive recommendation)
- `forum.thread.summarize` (creates a summary artifact or a post)
- `forum.thread.extract_decisions` (creates decision artifacts)

### 8.2 Moderation directives (v1 defaults to “recommend + queue”)
- `forum.moderation.flag.create`
- `forum.moderation.queue.enqueue`
- `forum.moderation.action.recommend` (tagging, moving, locking suggestion)
- `forum.thread.close` (admin-only; may require human confirmation)

### 8.3 Routing/engagement directives
- `forum.expert.notify` (internal notification; later integrates to Mattermost/email)
- `forum.thread.bump` (non-spammy engagement nudge)
- `forum.thread.tag.suggest`

### 8.4 Idempotency requirements
All directives must have deterministic idempotency keys. Examples:
- `forum.thread.summarize:{tenant}:{thread_id}:{summary_version}`
- `forum.expert.notify:{tenant}:{thread_id}:{group_or_user_id}:{reason}`

---

## 9) Data model (Ash resources) — forum domain

All forum resources are tenant-scoped unless explicitly stated.

### 9.1 `Forum.Category`
- `id` uuid
- `name` string
- `slug` string
- `description` text
- `position` integer
- `is_archived` boolean
- timestamps

### 9.2 `Forum.Thread`
- `id` uuid
- `category_id`
- `author_user_id`
- `title` string
- `slug` string
- `status` enum: `open | closed | archived`
- `is_pinned` boolean
- `is_solved` boolean
- `last_activity_at`
- counters: `view_count`, `reply_count`
- timestamps

### 9.3 `Forum.Post`
- `id` uuid
- `thread_id`
- `author_user_id` nullable (for agent/system)
- `author_agent_id` nullable
- `role` enum: `human | agent | system`
- `content_markdown` text
- `content_html` text (rendered)
- `edit_reason` text nullable
- `is_deleted` boolean (soft delete)
- agent metadata:
  - `agent_confidence` decimal nullable
  - `agent_model` string nullable
  - `agent_citations` jsonb nullable (thread/post links)
- timestamps

### 9.4 `Forum.Reaction`
- `id` uuid
- `post_id`
- `user_id`
- `type` enum: `like | upvote | downvote | laugh | ...` (keep small)
- timestamps

### 9.5 `Forum.ModerationFlag`
- `id` uuid
- `post_id`
- `flagger_user_id`
- `reason` enum: `spam | harassment | off_topic | duplicate | other`
- `notes` text nullable
- `status` enum: `open | reviewed | dismissed | action_taken`
- timestamps

### 9.6 `Forum.AgentInteraction` (optional but recommended)
A normalized table for analytics and UI:
- `id` uuid
- `thread_id`
- `post_id` nullable
- `agent_id`
- `interaction_type` enum: `responded | escalated | summarized | routed | moderated`
- `confidence_score` decimal nullable
- `feedback` enum: `helpful | not_helpful` nullable
- `signal_id` (link to persisted signal)
- timestamps

---

## 10) UI architecture (must align with current stack)

### 10.1 UI stack (canonical)
- Phoenix controllers render Inertia pages
- Svelte pages/components for UI
- Real-time updates:
  - MVP can use polling + Inertia refresh
  - Later: SSE (controller streaming) for new posts/notifications
  - Optional: Phoenix PubSub fanout feeding SSE

### 10.2 Required pages (MVP)
- `/forum` (categories + latest activity)
- `/forum/c/:slug` (category view)
- `/forum/t/:slug` (thread view)
- Thread composer + reply composer
- Moderation queue (admin-only)
- Agent settings per tenant (basic enable/disable + thresholds)

### 10.3 Rendering
- Store markdown; render to HTML server-side for safety and consistency.
- Sanitize HTML (no script injection).

---

## 11) Execution model (how agents operate)

Agents should run through FleetPrompt’s engine:

1. Forum event occurs (user creates thread/post) → emit `forum.*` signal.
2. Signal handler(s) determine whether any installed forum agents subscribe to that signal.
3. Create directive(s) for agent work (e.g., `forum.post.create`, `forum.thread.summarize`).
4. Directive runner enqueues an execution (LLM call) and writes logs.
5. Execution completes → directive marks complete → emit outcome signals.

**Key rule:** agent code should not “just write to the DB.” It should execute through directives/executions so outcomes are measurable and replayable.

---

## 12) Forum agents as packages (marketplace integration)

### 12.1 Packaging stance
Forum Agents are shipped as **FleetPrompt packages**:
- installable per tenant
- configurable (thresholds, categories enabled, escalation targets)
- measured (resolution rate, false positive rate, time-to-first-response)

### 12.2 Recommended initial packages
1) `forum_faq_agent`
- Detect duplicates / repetitive questions
- Suggest top 3 related threads and docs links
- Only posts when confidence above threshold

2) `forum_welcome_agent`
- Greets new users
- Suggests rules, best practices, relevant categories
- Optional: prompts for missing context

3) `forum_summary_agent`
- Generates TL;DR for long threads
- Creates weekly digest of top threads per category

4) `forum_moderation_agent`
- Flags likely spam/toxicity/low-effort content
- Does not delete by default; queues for review

5) `forum_routing_agent`
- Finds likely experts (based on participation history) and notifies
- Keeps notifications rate-limited and respectful

### 12.3 Package contract requirements
Each forum-agent package must declare:
- signals consumed (e.g., `forum.thread.created`)
- directives it may request (e.g., `forum.post.create`)
- required permissions (e.g., ability to post as agent, ability to create flags)
- rate limiting defaults and cost caps

---

## 13) Security & abuse controls (forum-specific)

### 13.1 Anti-abuse basics (MVP)
- per-user rate limits on posting
- per-IP throttling (privacy-aware; hash IPs where stored)
- new-account restrictions (cooldown / limited links)
- spam heuristics (link density, repeated content)

### 13.2 Agent safety requirements
- Agents must:
  - disclose uncertainty
  - cite sources (links to existing threads) when giving factual guidance
  - avoid hallucinated “policy” enforcement (moderation agent flags, humans decide)
- Never store secrets in:
  - forum posts,
  - signals payloads,
  - execution logs.
- Agent prompts should include only tenant-authorized context; do not leak cross-tenant data.

---

## 14) Observability & metrics (definition of success)

### 14.1 Core product metrics
- Time-to-first-response (human or agent)
- % threads answered within 24h
- Duplicate deflection rate (threads resolved by suggestion)
- Moderator workload:
  - flags per day
  - time to review
  - spam incidence
- Agent performance:
  - response helpfulness rate
  - escalation rate
  - false positive moderation flags rate
  - cost per resolved thread

### 14.2 Required operational surfaces
- “Agent Activity” dashboard:
  - actions taken
  - confidence distribution
  - replay links to correlation_id chain
- “Signals explorer” filtered by `forum.*`
- “Directive queue” view for forum directives

---

## 15) Implementation sequencing (how Phase 6 fits the roadmap)

### 15.1 Dependencies
Phase 6 assumes:
- Milestone A (Packages)
- Milestone A2 (Signals + Directives)
- Milestone B (Execution thin slice)

It can run **in parallel** with Milestone C (Chat UX), but should not require it.

### 15.2 Recommended delivery plan
**Phase 6A — Forum Core MVP**
- Implement forum resources (Category/Thread/Post/Reaction/Flag)
- Build Inertia/Svelte pages for browsing + posting
- Emit `forum.*` signals for core actions

**Phase 6B — Agent Participation**
- Implement one agent package (`forum_faq_agent`)
- Wire signal handlers: `forum.thread.created` → directive → execution → agent post
- Add feedback UI (helpful/not helpful)

**Phase 6C — Moderation + Summaries**
- Add moderation agent package (flagging)
- Add summary agent package (TL;DR + weekly digest)

**Phase 6D — Marketplace + Admin polish**
- One-click install of forum agent packages from marketplace
- Per-tenant config UI
- Metrics dashboards

---

## 16) Exit criteria (Phase 6 is “done enough”)

Phase 6 is successful when:

1. A tenant can run a forum with:
   - categories, threads, posts, reactions, moderation flags
2. Installing `forum_faq_agent` yields measurable value:
   - at least one thread gets a useful agent response,
   - agent actions are visible and auditable (signals + directives + executions),
   - feedback is collected and stored
3. The system remains safe and operable:
   - idempotency prevents duplicate agent posts on retries/replays
   - moderation agent does not silently delete content
   - tenant isolation invariants hold under load

---

## 17) Open questions (must decide before scaling)

1) **Forum as separate app vs integrated:** keep integrated until scale forces separation.
2) **Search strategy:** Postgres FTS first; vectors optional later.
3) **Agent identity model:** reuse `Agents.Agent` vs separate `Forum.AgentPersona` resource.
4) **Public communities:** do we allow anonymous read / SEO by default, or require auth?
5) **Moderation policy:** where is the “human in the loop” boundary for automated actions?

---

## 18) Summary

FleetPrompt Forum is the best “killer app” candidate because it:
- validates FleetPrompt’s core primitives end-to-end,
- creates a natural distribution loop,
- makes agent orchestration visible and measurable,
- and converts platform reliability (signals/directives/executions) into a product that people immediately understand:  
**“the forum that runs itself, safely.”**