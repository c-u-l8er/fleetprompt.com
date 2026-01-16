# FleetPrompt — Phase 2E: Website Chat Widget Package (Communication Triangle)
File: `fleetprompt.com/project_plan/phase_2e_website_chat_package.md`  
Status: Spec (new)  
Last updated: 2026-01-06

## 0) Purpose

FleetPrompt’s “communication triangle” is:

- **Mailbox** (email): Proton Mail via **Edge Connector** (Bridge-based)
- **Instant messenger** (team chat): Mattermost (webhooks/PAT)
- **Website chat widget**: on-site conversations with visitors

This Phase 2E spec adds the **website chat** leg as an **integration package**—not a platform pivot—so FleetPrompt can deliver an end-to-end communications posture:

- capture intent at the website edge,
- route to the right system (Mattermost + email),
- preserve auditability via **Signals** and controlled side effects via **Directives**,
- keep customer-visible UX fast and simple.

This spec is designed to align with the Phase 2A/2B primitives:
- **Phase 2A:** Packages + Installations
- **Phase 2B:** Persisted **Signals** + auditable **Directives**

---

## 1) Non-goals (explicit)

This spec does **not**:
- make FleetPrompt “a chat-widget company” as the core business,
- require building a full competitor to Charla/Intercom/Drift,
- require advanced contact-center features (routing trees, agent queues, SLA timers, voice),
- require multi-channel social inbox support as part of v1,
- require third-party package code execution (packages remain metadata + templates + platform-owned handlers).

---

## 2) Package overview

### Package name
**Website Chat Package**

### Package slug
`website_chat`

### Category
`:customer_service` (also relevant to `:sales`)

### Outcomes (what value it must deliver)
- A website can embed a chat widget within minutes.
- Visitor messages become **tenant-scoped Signals** immediately (durable, replayable).
- Operators can respond through FleetPrompt (later) or via integrations (Mattermost/email).
- The system can provide an auditable timeline:
  - who replied,
  - when,
  - what automation ran,
  - what external posts/emails were triggered.

---

## 3) Two operating modes

FleetPrompt should support **two modes** so customers can pick the fastest path:

### Mode A (FleetPrompt Native Widget) — recommended default
FleetPrompt hosts and serves:
- widget JS,
- chat UI,
- message ingestion endpoint,
- conversation state persistence.

**Pros**
- Full control of data model and observability.
- Native routing into Signals/Directives.
- No third-party vendor dependency.

**Cons**
- More engineering scope than embedding an existing tool.

### Mode B (Optional): Charla Embed Mode — “fast path”
FleetPrompt does **not** replace Charla. Instead, the package supports:
- embedding Charla’s widget script on the customer website,
- optionally adding a “bridge” layer so Charla conversations can trigger FleetPrompt workflows.

**Important constraint**
Without a documented Charla API/webhook surface (not assumed in this spec), FleetPrompt can only guarantee:
- **embedding** the widget (presentation),
- optional “link out” or “handoff” actions,
- and (if available) event ingestion via standard webhooks/exports.

So: **Embed Mode is optional and capability-gated** by what Charla exposes to customers.

---

## 4) Experience goals (MVP)

### Installation UX (tenant admin)
1. Install `website_chat` from marketplace.
2. Choose mode:
   - `native`
   - `charla_embed`
3. Configure site(s):
   - domain(s) allowed
   - widget settings
4. Copy/paste embed snippet into website `<head>` or at end of `<body>`.
5. Verify installation:
   - “test message” sends a signal to FleetPrompt
   - optional: posts a notification into Mattermost (if configured)

### Visitor UX
- Widget loads quickly.
- Visitor can send a message without creating an account.
- Clear consent/notice if the tenant needs it (GDPR).
- Optional: capture email/name if user provides it (or on demand).

---

## 5) Data model impact (tenant schema)

This package assumes Phase 2B primitives exist:

1) `signals` (tenant-scoped)
2) `directives` (tenant-scoped)

Recommended additional tenant-scoped resources/tables for this package:

### 5.1 `website_chat_sites`
Stores site configuration per tenant:
- id (uuid)
- domain (string)
- status (active/disabled)
- mode (`native` | `charla_embed`)
- settings jsonb (appearance, prompts, consent flags)
- inserted_at/updated_at

### 5.2 `website_chat_conversations`
- id (uuid)
- site_id (uuid)
- visitor_id (uuid or opaque string)
- visitor_email (nullable)
- visitor_name (nullable)
- status (`open` | `closed`)
- inserted_at/updated_at

### 5.3 `website_chat_messages`
- id (uuid)
- conversation_id
- role (`visitor` | `assistant` | `agent`)
- content (text)
- metadata jsonb (ip hash, user agent, page url)
- inserted_at

### 5.4 (Optional) `website_chat_identities`
If you want stable visitor identity:
- visitor_id
- hashed identifiers (cookie id, email hash)
- last_seen_at

**Security note:** IP addresses and raw user-agent strings may be treated as personal data. Default to hashing/redacting where possible.

---

## 6) Signal taxonomy (v1)

### Inbound (visitor)
- `webchat.session.started`
- `webchat.message.received`
- `webchat.contact.captured` (if email/name is provided)
- `webchat.session.ended`

### Outbound (operator/automation)
- `webchat.reply.generated` (if AI drafts)
- `webchat.reply.sent` (if sent through widget)
- `webchat.escalation.created` (handoff)
- `webchat.escalation.notified` (e.g., posted to Mattermost)
- `webchat.escalation.failed`

### Mode B (Charla embed) signals
If Charla supports events/webhooks later:
- `charla.message.received`
- `charla.conversation.created`
- `charla.handoff.triggered`

If Charla does **not** provide an event feed:
- do not emit `charla.*` signals; embed mode is “presentation only”.

---

## 7) Directive taxonomy (v1)

Directives remain the only way to cause side effects (to preserve auditability).

### Core directives
- `webchat.site.register`
- `webchat.site.rotate_secret`
- `webchat.site.disable`
- `webchat.escalate_to_mattermost`
- `webchat.escalate_to_email`

### Optional directives (later)
- `webchat.reply_send`
- `webchat.reply_generate` (LLM draft)
- `webchat.conversation.close`

---

## 8) Security model (non-negotiable)

### 8.1 Tenant binding
All inbound chat requests must be tied to a tenant safely:
- use a per-site **public widget key** + per-site **signing secret**
- do not accept tenant identifiers from client input beyond this binding
- derive tenant schema from the site record

### 8.2 Request authenticity
For native widget ingestion endpoints:
- issue a signed token to the widget via a bootstrap endpoint:
  - contains site_id, issued_at, expiry
  - signed server-side
- widget attaches token to message POSTs

### 8.3 Abuse controls
- per-site rate limiting (messages/minute)
- CAPTCHA challenge option for high abuse (optional)
- IP-based throttling (careful with privacy posture)
- spam heuristics (later)

### 8.4 Secrets
- Never store secrets in signals
- Per-site secrets are encrypted at rest
- Logs must redact tokens and Authorization headers

---

## 9) Integration with Mattermost (handoff path)

The website chat package should support escalation into Mattermost as the first “operator surface”, because it completes the triangle quickly.

### Minimal v1 handoff
On `webchat.message.received`:
- if auto-notify enabled, create directive `webchat.escalate_to_mattermost`:
  - includes: site_id, conversation_id, safe summary, link to FleetPrompt conversation page
- directive runner posts to Mattermost (incoming webhook URL) and emits:
  - `webchat.escalation.notified` or `webchat.escalation.failed`

**Important:** do not post raw secrets; content is ok but be mindful of PII settings per tenant.

---

## 10) Integration with Proton Mail (handoff path via Edge Connector)

Because Proton Mail is Bridge-based, escalation to Proton Mail typically requires the **Edge Connector**.

### Recommended v1 behavior
- FleetPrompt creates directive `webchat.escalate_to_email`
- directive enqueues a task for the Edge Connector to send:
  - either a summary email to a configured address,
  - or create a ticket email into a configured system

Signals:
- `webchat.escalation.created`
- `email.outbound.requested`
- `email.outbound.sent` / `email.outbound.failed`

**Key principle:** FleetPrompt remains the source of truth; the edge connector is an executor for email send/receive.

---

## 11) Charla Embed Mode (optional)

### 11.1 What FleetPrompt will provide (guaranteed)
- A configuration UI to generate the snippet needed to embed Charla’s widget.
- Tenant-level bookkeeping:
  - which sites use Charla
  - which Charla “property_key” is configured (if needed)
- Optional: a “handoff to FleetPrompt” link inside the widget via:
  - a URL that opens FleetPrompt chat/support page (if the customer wants it)

### 11.2 What FleetPrompt will NOT promise without a Charla API
- programmatic ingestion of Charla messages into FleetPrompt
- real-time synchronization of Charla inbox into FleetPrompt
- reliable webhook-driven workflows from Charla

If Charla later provides:
- webhooks,
- API endpoints,
- exports,
then FleetPrompt can implement:
- `charla.*` signals and robust ingestion with dedupe keys.

### 11.3 Charla embed snippet pattern
This spec cannot hardcode Charla’s script format as canonical (vendor can change it), but the package should support an embed template like:

- load vendor script
- set vendor config object (e.g., property key)
- optionally pass known visitor fields (email/name) when available

Any embed mode must:
- restrict domains (site allowlist)
- minimize data leakage (do not pass PII unless user consent captured)

---

## 12) UX surfaces inside FleetPrompt

### 12.1 Website Chat Inbox (v1)
A minimal inbox UI for tenant members:
- list conversations by site and status
- view messages
- show audit trail of signals/directives related to a conversation
- show “Escalate to Mattermost” / “Escalate to Email” buttons (directive-backed)

### 12.2 “Conversation deep link”
Every escalation notification should include a link to:
- `/support/webchat/conversations/<id>` (route name TBD)

This becomes the bridge between external channels and FleetPrompt’s internal truth.

---

## 13) Idempotency & dedupe (required)

### 13.1 Message ingestion
Each message should have a deterministic dedupe key:
- `dedupe_key = "webchat_msg:{tenant}:{site_id}:{conversation_id}:{client_message_id}"`

Where `client_message_id` is a UUID generated client-side (or server-issued sequence).

### 13.2 Escalation posting to Mattermost
Use:
- `dedupe_key = "webchat_mm_escalation:{tenant}:{conversation_id}:{destination}"`

So retries don’t spam channels.

### 13.3 Email escalation
Use:
- `dedupe_key = "webchat_email_escalation:{tenant}:{conversation_id}:{destination}"`

Edge Connector must also be idempotent.

---

## 14) Testing plan (minimum)

### Unit tests
- widget token signing/verification
- domain allowlist enforcement
- signal payload validation (JSON-safe, no secrets)
- directive idempotency keys (repeated requests return existing directive)

### Integration tests
- visitor message → `webchat.message.received` persisted signal
- escalation directive → Mattermost post stubbed → correct signals emitted
- replay safety:
  - replay `webchat.message.received` does not duplicate escalations if dedupe keys are honored

### Security tests
- ensure no tenant spoofing is possible via request parameters
- ensure tokens are not logged or stored in signals
- rate limit enforcement for message spam

---

## 15) Rollout plan

### Stage 1: Native widget only
- ship minimal widget + ingestion + signals + escalation to Mattermost
- prove reliability and observability

### Stage 2: Edge Connector integration for Proton Mail escalations
- enable email escalation path via connector
- ensure robust ops story for connector auth + connectivity

### Stage 3: Optional Charla embed mode
- add embed generator UI
- if Charla event ingestion is possible, add it as a separate increment with clear constraints and dedupe

---

## 16) Summary

Phase 2E completes the “communication triangle” by adding website chat as a **package**, not a pivot. It supports:

- a **native** FleetPrompt widget for full control and observability,
- an **optional Charla embed** mode for customers who want a fast drop-in widget,
- durable operational truth via **Signals** and controlled actions via **Directives**,
- immediate operator workflows via Mattermost, and privacy-first email via a Proton Mail **Edge Connector**.

This package is successful when a tenant can capture website conversations, route them into their chosen operator surface, and still retain a full auditable, replayable record inside FleetPrompt.