# FleetPrompt — Phase 2C: Lighthouse Slice Spec (Forums‑First)

File: `fleetprompt.com/project_plan/phase_2c_lighthouse_package.md`  
Status: Spec (rewritten)  
Last updated: 2026-01-07

## 0) Purpose (why Phase 2C exists)

Phase 2A makes packages *installable*.  
Phase 2B makes installs *real and operable* (Signals + Directives).

**Phase 2C proves the whole loop end‑to‑end** with one “lighthouse slice” that is:
- **tenant-visible** (real UI + real tenant data),
- **signal-first** (durable facts for everything meaningful),
- **directive-driven** (auditable intent for any side effects),
- **operable** (replayable signals, retryable directives, safe idempotency),
- and **demoable** (can be shown without third-party dependencies).

**This spec changes the lighthouse stance**: Phase 2C is no longer “an integration-first external tool demo”.  
Phase 2C is **Forums-first**: we use FleetPrompt’s own Forums feature as the lighthouse to validate platform primitives (Signals + Directives + jobs + tenancy) before prioritizing email/chat/IM integrations.

---

## 1) Lighthouse slice choice (v1)

### Lighthouse: FleetPrompt Forums (Dogfood + Demo)
**Slice name:** Forums Lighthouse  
**Slice slug:** `forums_lighthouse` (internal label; not necessarily a marketplace slug)  
**Primary surface:** FleetPrompt web app (Inertia + Svelte)  
**Primary outcome:** A tenant can use a minimal forum end-to-end, and FleetPrompt can answer “what happened?” for every important action using Signals + Directives.

### Why Forums is the right lighthouse
Forums is intentionally chosen because it:
- has **no external dependency** (fastest path to a reliable demo),
- forces correctness on **tenancy, identity, and permissions**,
- produces meaningful **signals** immediately (threads/posts/edits/moderation),
- exercises **directives** for controlled, auditable mutations,
- creates a natural foundation for later “operator console” UX (support, escalation),
- can later integrate outward (email/chat/IM) once the internal truth loop is proven.

### Scope stance
- We can ship a **human-only forum first** (threads + posts + moderation basics).
- Agent participation is allowed only once the **Execution thin slice** is available, and even then must remain **directive-gated**.
- The lighthouse is successful even if “agents replying automatically” is deferred, as long as the **Signals/Directives audit loop** is real and visible.

---

## 2) Non-goals (explicit)

To keep Phase 2C shippable, v1 does **not** include:
- building a full community platform (badges, reputation, advanced search, spam ML, etc.),
- real-time chat widget work,
- email, instant messenger, or chatbot integrations as **required** dependencies,
- third-party package code execution (packages remain metadata + platform-owned handlers),
- full moderation suite (queues, SLAs, automation trees),
- “public internet forum” (this is tenant-private, org-member scoped by default).

---

## 3) Success criteria (exit criteria)

Phase 2C is complete when all of the following are true.

### A) Enable → use → audit
- A tenant can access Forums pages and perform core actions:
  - create a category (optional if seeded),
  - create a thread,
  - create a post reply.
- For each of the above, FleetPrompt records **tenant signals** with required metadata and dedupe discipline where applicable.
- The UI includes at least one “audit trail” surface:
  - per thread OR per post: show related Signals + Directives in time order.

### B) Directives govern side effects
The following must be directive-backed (auditable intent), not “hidden updates”:
- moderation actions (lock/unlock thread, hide/unhide post, delete post),
- agent participation (request agent reply, publish agent reply),
- any outbound integration (future) triggered from forum activity.

### C) Idempotency + retry semantics
- Re-running a directive job must not create duplicate posts.
- A failed directive must be retryable in a **controlled** way (explicit rerun), not via uncontrolled automatic retries that could duplicate side effects.
- Signals must be replayable in a dev/support workflow without corrupting state (handlers idempotent).

### D) Time-to-value
Target: **< 15 minutes** from a fresh tenant to:
- creating a forum thread,
- seeing Signals and Directives recorded for it,
- and being able to replay or rerun safely (at least in dev).

---

## 4) Architectural contract (forums-first, Phase 2B aligned)

### 4.1 Signals are immutable facts (tenant-scoped)
Signals represent “what happened”. They are append-only and durable.

**Required properties on all forum signals:**
- `name` (taxonomy below),
- `occurred_at`,
- `payload` (JSON-safe, no secrets),
- `metadata` (JSON-safe: request ids, safe tags),
- `dedupe_key` when the origin can be duplicated (client retries, job retries).

**No secrets in signals.** Forum content is allowed (it’s the product), but do not store tokens/credentials.

### 4.2 Directives are controlled intent (tenant-scoped)
Directives represent “what should happen” and are the only permitted path for:
- moderation side effects,
- agent actions,
- outbound notifications (later).

Directives must include:
- `name`,
- `idempotency_key` (recommended for any directive that can be clicked twice),
- `payload` (parameters),
- `requested_by_user_id` where applicable,
- lifecycle state with timestamps.

### 4.3 Relationship between them
- Directives emit directive lifecycle signals (`directive.started`, `directive.succeeded`, `directive.failed`) and/or domain signals.
- Domain handlers may emit additional signals (e.g. `forum.post.hidden`).

---

## 5) Data model impact (tenant schema)

This lighthouse slice assumes Phase 2B primitives exist in tenant schema:
- `signals`
- `directives`

### 5.1 Tenant-scoped Forum resources (minimum viable)
These can be Ash resources backed by Postgres (preferred), or first introduced as Ecto schemas if needed—BUT the long-term plan should be Ash.

**`forum_categories`**
- `id` (uuid)
- `slug` (string, unique)
- `name` (string)
- `description` (text, nullable)
- `status` (`active` | `archived`)
- timestamps

**`forum_threads`**
- `id` (uuid)
- `category_id` (uuid)
- `title` (string)
- `status` (`open` | `locked` | `archived`)
- `created_by_user_id` (uuid)
- timestamps

**`forum_posts`**
- `id` (uuid)
- `thread_id` (uuid)
- `content` (text)
- `status` (`published` | `hidden` | `deleted`)
- `author_type` (`human` | `agent` | `system`)
- `author_id` (string/uuid depending on actor type; no cross-schema FK)
- timestamps

### 5.2 Optional but recommended (for durability + idempotency)
**`forum_directive_links`** (or store in directive payload)
- maps directives to the entities they created/affected, to support replay/audit.

This is not strictly required if directive payload/result is sufficient, but it becomes useful for:
- “find directive that created this post”,
- safe reruns and status transitions.

---

## 6) Signal taxonomy (forums v1)

### 6.1 Thread and post signals
- `forum.category.created`
- `forum.thread.created`
- `forum.post.created`

### 6.2 Moderation signals (minimum)
- `forum.thread.locked`
- `forum.thread.unlocked`
- `forum.post.hidden`
- `forum.post.unhidden`
- `forum.post.deleted`

### 6.3 Agent interaction signals (Phase 2C optional; Phase B required later)
- `forum.agent.reply.requested`
- `forum.agent.reply.posted`
- `forum.agent.reply.failed`

### 6.4 Required metadata on all forum signals
At minimum:
- `tenant`
- `request_id` (if available)
- `actor` (type/id) when the action is user-initiated
- `subject` (type/id) (thread/post/category)
- correlation/causation ids where appropriate (especially for directives/jobs)

---

## 7) Directive taxonomy (forums v1)

### 7.1 Moderation directives (must be directive-backed)
- `forum.thread.lock`
- `forum.thread.unlock`
- `forum.post.hide`
- `forum.post.unhide`
- `forum.post.delete`

### 7.2 Agent directives (only after execution thin-slice is available)
- `forum.agent.reply_generate` (produces a draft / candidate)
- `forum.agent.reply_publish` (creates the post, idempotent)

### 7.3 Idempotency key schemes (recommended)
- `forum.thread.lock:{tenant}:{thread_id}`
- `forum.post.hide:{tenant}:{post_id}`
- `forum.agent.reply_publish:{tenant}:{thread_id}:{request_id or client_id}`

---

## 8) Implementation plan (forums-first lighthouse)

This plan describes the minimum needed to make Forums a credible lighthouse.

### Step 1 — Replace mocked Forums controller payloads with real reads
- Back the existing Inertia pages (`/forums`, `/forums/new`, `/forums/c/:slug`, `/forums/t/:id`) with tenant-scoped reads.
- Ensure org membership gating remains intact.

### Step 2 — Add tenant-scoped forum resources + migrations
- Implement the resources listed in Section 5.
- Ensure tenant migrations apply cleanly across existing tenants.

### Step 3 — Emit signals for all core creates
- When category/thread/post is created:
  - emit the corresponding `forum.*.created` signal with an appropriate dedupe key.

### Step 4 — Implement moderation via directives + runner
- Create directives for lock/hide/delete.
- Add a runner handler (Oban) for these directives:
  - enforce idempotency,
  - persist results,
  - emit signals.

### Step 5 — Add an audit trail UI
- On thread view, show a timeline sourced from:
  - `signals` (filtered by thread_id / subject references),
  - `directives` (filtered via payload references or directive links).
- This is the user-visible proof of Phase 2B value.

### Step 6 — Optional (only after Execution thin-slice exists): agent reply flow
- “Request agent reply” creates a directive.
- Runner executes (using execution engine) and publishes a post only via directive.
- Emit `forum.agent.*` signals.

---

## 9) Testing plan (minimum)

### Unit tests (required)
- Signal emission:
  - SignalBus idempotency by `dedupe_key`.
  - SignalFanout runs handlers and surfaces handler errors.
- Directive runner:
  - directive lifecycle transitions (requested → running → succeeded/failed).
  - rerun semantics: failed directives require explicit rerun flag.
- Forum model invariants:
  - tenant scoping works (cannot read across tenants),
  - unique constraints (category slug, etc.).

### Integration tests (required)
- create thread/post -> signals exist and are tenant-scoped.
- moderation directive -> state changes + signals emitted + directive marked succeeded.

### Security tests (minimum)
- membership gating on forums routes,
- directives restricted to org roles for moderation actions,
- no secrets/tokens in signals.

---

## 10) Rollout plan

### Stage 1: Internal / dev (default)
- Ship real forum backing resources
- Ship audit trail UI
- Prove replay and controlled rerun in dev

### Stage 2: Dogfood (team + early tenants)
- Add basic abuse controls (rate limiting/throttling for posts)
- Confirm operability under real usage

### Stage 3: Agent participation (guardrailed)
- Only after execution thin-slice is stable
- Keep “publish” directive-gated and idempotent

---

## 11) Summary

Phase 2C is now a **Forums-first lighthouse**. The goal is to prove FleetPrompt’s platform primitives in a real product surface:

- tenant-scoped truth via **Signals**,
- controlled mutations via **Directives**,
- replayability and operability,
- and a credible, demoable, retention-capable feature that does not depend on external integrations.

Email, chatbot, and instant messenger integrations remain valuable—but they become priorities **after** Forums proves the core loop end-to-end.