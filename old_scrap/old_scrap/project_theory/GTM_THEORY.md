# FleetPrompt GTM Theory (Go-to-Market + Packaging Strategy)

Last updated: 2026-01-06

## Purpose

This document defines **how FleetPrompt should win**: who you sell to, what you sell (packaging), how you price it, how you distribute it, and what milestones prove you’re on-track. It is written to stay stable even as implementation details evolve.

FleetPrompt’s core constraint is not model quality; it’s **adoption friction**. The GTM theory optimizes for **fast time-to-value inside tools customers already use**, then expands into deeper automation and a premium “platform” offering.

---

## Executive Thesis

### The winning position
FleetPrompt is a **pre-built AI operations layer** delivered as **installable integration packages** that run inside a customer’s existing stack (Mattermost, Proton Mail, Shopify, HubSpot, etc.). You are not “another AI chat widget” and you are not “yet another dashboard.” You are a **package marketplace** for agentic workflows that integrate where work already happens.

### Strategy in one line
**Integration-first packages for distribution + retention, standalone platform later as an upsell tier.**

---

## Core GTM Assumptions (and why they matter)

### A1) Integration is the #1 adoption bottleneck
Most teams will not migrate data, change their workflows, or adopt new UIs unless the value is overwhelming. Integration packages win because they:
- reduce behavior change to near-zero
- inherit context from existing systems
- “show up” where users already spend 6–8 hours/day

### A2) Packages are the SKU, not “the product”
The marketplace is the product. Packages are the unit of:
- purchase decision
- onboarding
- value measurement
- retention

### A3) Narrow ICP first, then expand
Early growth comes from one or two “meta-advantage” verticals (high need + high willingness to pay + strong referrals). After product-market fit in a vertical, you generalize packages into horizontal versions.

### A4) Avoid the “commoditized chat” trap
Website chat agents (Charla-style) are best treated as **one package**, not the center of gravity. The moat is not the widget; it’s the marketplace + integration depth + operational reliability.

---

## ICP (Ideal Customer Profile) and Beachhead

### Primary beachhead: Marketing agencies (meta-advantage)
**Why:** Agencies have repeatable workflows, high tool sprawl, measurable outcomes, and strong referral/partner loops.

**Who exactly:**
- 5–50 person agencies
- already using Mattermost (or Teams/Slack alternatives) + Proton Mail (or other email) + at least one analytics/ads platform
- service delivery requires recurring reporting + client comms + approvals + campaign ops

**Buy triggers:**
- reporting time sink
- missed follow-ups / SLA breaches
- margin pressure (need automation without hiring)

### Secondary: E-commerce operators (Shopify-first)
**Why:** Fast feedback loops, clear ROI, and integration surfaces are well-defined (orders, tickets, returns, inventory).

### Deferred (later): Regulated/service verticals (legal, healthcare)
High upside but requires compliance posture, audit trails, and stronger data governance. You can get there; don’t start there.

---

## Positioning and Messaging

### Primary positioning
**“Install AI operations packages that work inside your existing tools.”**

### Secondary positioning (for technical buyers)
**“A marketplace and runtime for agentic workflows with multi-tenant isolation and auditability.”**

### What you are not
- Not “a chatbot product”
- Not “a generic automation builder”
- Not “a replacement CRM / replacement inbox” (at least not initially)

### Proof-oriented claims to lead with
- “No migration. No new login. Works in Mattermost/Proton Mail/Shopify.”
- “Installed in minutes. Measurable in days.”
- “Packages ship with guardrails: roles, approvals, logs.”

---

## Packaging Model (the product design for GTM)

### Definitions
- **Package**: Installable capability set (integration + workflow(s) + UI surfaces) designed to deliver one job-to-be-done.
- **Bundle**: A set of packages sold together for an ICP/vertical.
- **Workspace/Org**: Customer account boundary (billing + tenant boundary).
- **Seat**: Optional; use only if it maps to value (avoid per-seat early if it adds friction).

### The SKU structure
You should ship **3 layers** of packages:

1) **Surface Packages** (distribution wedges)
- Lightweight, integrate into a single surface (e.g., Mattermost, Proton Mail)
- Clear, quick win; easy to trial
- Example: “Mattermost Daily Ops Digest”

2) **Workflow Packages** (retention engine)
- Multi-step automations, approvals, durable state, logs
- Example: “Client Reporting Autopilot (Slack + GA4 + Ads)”

3) **System Packages** (expansion engine)
- Cross-team automation, multi-agent orchestration, deeper governance
- Example: “Agency Delivery OS (brief → tasks → approvals → reporting)”

### Package design rules (non-negotiable)
A package is only “sellable” if it has:
- **a single clear job-to-be-done**
- a default workflow that works with minimal configuration
- a visible surface where the user experiences value (Slack messages, email drafts, dashboards)
- logs + auditability (at least per execution)
- clear installation + uninstall semantics (no “ghost” automations)

---

## Pricing Theory

### Pricing principles
- Price to the value of the job-to-be-done, not to tokens.
- Keep early pricing simple and changeable, but do not ignore unit economics.
- Prefer **package-level pricing** as the primary SKU, with **guardrails** that prevent negative-margin tenants.
- Make “cost visibility” part of the product: track cost per execution/package/org from day 1 so pricing can evolve without guesswork.

### Known pricing risk (explicit)
FleetPrompt has variable costs (LLM + integrations + compute). A flat monthly price can create negative unit economics if a tenant runs high-volume workloads.

**Policy:** start with simple pricing, but bake in enforcement mechanisms early:
- included usage quotas per package/bundle (executions/day, messages/day, token budget, etc.)
- per-tenant rate limits and concurrency caps
- clear “pause/require approval” behavior when limits are reached

### Freemium / trial wedge (recommended)
To reduce adoption friction and solve “why trust this?”:
- Offer at least one **free** surface package or a **free tier** with strict limits (e.g., limited executions/month).
- Alternatively (or additionally), offer a **time-boxed trial** (e.g., 7–14 days) on a bundle, gated by usage caps.
- For developer-heavy tenants, consider **bring-your-own-LLM-key** mode (optional) to reduce FleetPrompt’s cost exposure while increasing adoption.

### Recommended early pricing shapes
Start with these, then iterate based on observed usage patterns over 3–6 months:
- **Per package per month** for integration packages (simple)
- **Bundle discount** for vertical bundles (drives expansion)
- **Usage-based overages later** (not day 1), once you know real cost drivers:
  - token overages (LLM)
  - high-volume event ingestion (webhooks/messages)
  - high-frequency scheduled runs

### Suggested starting bands (guidance, not a promise)
- Surface packages: $49–$149/mo (plus strict included usage)
- Workflow packages: $149–$499/mo (plus included usage and higher caps)
- System packages / bundles: $499–$1,999/mo (only once lighthouse packages prove ROI)

### Usage-based overages (when you add them)
Add overages only after you can explain them simply and measure them reliably:
- include a monthly allowance per plan (e.g., included token budget or included executions)
- charge for overages beyond the allowance
- provide “hard stop” and “soft stop” options per tenant (admin chooses):
  - hard stop = pause automation at limit
  - soft stop = continue with overage billing

### The premium tier (later)
A “FleetPrompt Complete” tier becomes viable when:
- you have 10+ packages with proven retention
- you can bundle into vertical “operating systems”
- you can justify centralized governance, unified UX, and higher included usage as a premium

---

## Distribution Strategy (how you acquire customers)

### Channel 1: “Install-first” self-serve (core)
- Marketplace browsing → package install → guided config → first value event
- Conversion levers:
  - templates per vertical (“Agency Starter Pack”)
  - instant demo data/sandbox mode
  - a **freemium wedge** (free package or free tier with strict limits)
  - a **time-boxed trial** for bundles (also with usage caps)
  - in-product “recommended next package”

### Channel 2: Agency partner loop (especially for marketing)
Agencies are both:
- customers and
- distribution partners (they can resell/standardize packages across clients)

Mechanics:
- partner pricing / margin
- “client workspace provisioning” workflows
- co-marketing with small agency communities

### Channel 3: Integration listings (later)
Mattermost Marketplace (plugins/integrations), Shopify App Store, other integration directories, etc.  
These are powerful but demand polish and compliance. Plan for them after internal package maturity.

---

## Activation, Retention, Expansion (the funnel you should measure)

### Activation: the “first value event” must be concrete
Examples:
- Mattermost package: “first scheduled insight posted to a real channel”
- Proton Mail package: “first drafted reply saved and approved” (note: may require Proton Mail Bridge and/or an edge connector)
- Shopify package: “first order issue resolved with a suggested response + action”

Target: first value event within **15 minutes** of install.

### Retention: measured by outcomes, not sessions
Good retention metrics:
- weekly executions per package
- percent of executions that reach “completed”
- percent of executions requiring human intervention (should drop over time)
- “saved time” proxy events (auto-generated report delivered, follow-up created)

### Expansion: package adjacency graph
Your expansion should be intentional:
- each package recommends 1–2 adjacent packages
- bundles are the “north star” for expansion

Example agency adjacency:
- Reporting → Client Comms → Campaign Ops → Lead Intake → Billing summaries

---

## Competitive Theory

### Where you win
- Pre-built packages vs DIY automation
- Integration depth + operational runtime vs “prompt glue”
- Multi-tenant + logs + job execution vs “chat-only” tooling

### Where you should not fight early
- Generic website chat widget market (commoditized)
- “Replace Salesforce/HubSpot” replacement positioning (migration friction)
- Enterprise procurement cycles before you have governance/audit maturity

---

## Product → GTM Alignment (what must be true in the product)

This section is the bridge between GTM and engineering.

### Minimum platform capabilities required before selling packages
- Organizations + membership + tenant selection (foundation)
- A real package registry + installation lifecycle
- Execution tracking + logs (at least per workflow run)
- Basic observability (errors surfaced, retries controlled)

### “Package maturity checklist” (ship gate)
A package is GA-ready if it has:
- onboarding/config steps and validation
- safe defaults + rate limiting where needed
- audit logs per execution
- uninstall rollback behavior (or clearly documented non-reversible actions)
- clear success metrics (what “working” means)

---

## Launch Sequencing (what to launch first and why)

### Phase 1 (now): Make the marketplace real and sellable
Goal: convert FleetPrompt from “framework” into “storefront + install”.

Focus:
- package resource + install resource + install job
- marketplace index + detail
- installation flow + first value instrumentation

Outcome: you can demonstrate “install package → it does a thing” end-to-end.

### Phase 2: Ship 3–5 lighthouse packages (one ICP first)
Pick one beachhead ICP (recommended: marketing agencies) and ship packages that:
- deliver obvious value quickly
- rely on integrations with high availability
- have repeatable configuration

Suggested initial agency lighthouse set:
1) Client Reporting Autopilot (Mattermost + analytics sources)
2) Client Follow-up Copilot (Proton Mail + optional edge connector via Proton Mail Bridge; or Outlook as a fallback)
3) Lead Intake Triage (forms + email + Mattermost alerts)
4) Campaign Monitoring Alerts (threshold-based insights)
5) (Optional) Website Chat as a package, not the core product

### Phase 3: Bundles + partner motion
Once you have lighthouse packages:
- publish “Agency Starter Bundle”
- enable partner provisioning workflows
- develop case studies with measurable outcomes

---

## Growth Experiments (what to test early)

### E1) “Install-to-value” time test
Measure time from install → first value event.  
If >15 minutes, onboarding or defaults are wrong.

### E2) Landing page positioning split
- Variant A: “AI packages inside your tools”
- Variant B: “Marketplace for agent workflows”
Choose based on conversion to install.

### E3) Bundle vs single-package conversion
Do bundles increase conversion or confuse buyers?  
Start with “recommended bundle” rather than forced bundling.

### E4) Agency partner loop pilot
Recruit 5 agencies, offer partner terms, and measure:
- number of client workspaces provisioned
- monthly retention across client workspaces

---

## Risks and Mitigations

### Risk: “Too horizontal” marketplace with no wedge
Mitigation: start with a vertical wedge and lighthouse packages; generalize later.

### Risk: Integration maintenance overhead
Mitigation: design packages to degrade gracefully; add circuit-breakers, retries, and clear status surfaces.

### Risk: Pricing confusion
Mitigation: keep pricing simple per package; add usage tiers only after you see real cost drivers.

### Risk: Becoming “prompt wrappers”
Mitigation: require durable workflows, logs, and measurable outcomes for GA packages.

---

## Success Metrics (what “winning” looks like)

### Early (pre-scale)
- 10 design partners installing packages
- 3 lighthouse packages with weekly active executions
- install → first value < 15 minutes median
- >50% of installs still active after 30 days (per package)

### Growth
- package attach rate: avg installed packages per org increases month-over-month
- net revenue retention driven by bundles and adjacency installs
- partner channel contributes a meaningful share of new orgs

---

## Non-Goals (to keep focus)

- Do not pivot to a website-chat-only business model.
- Do not lead with “replace your stack.”
- Do not overbuild a unified standalone UI before packages and integrations prove demand.

---

## Summary

FleetPrompt’s GTM is a **package marketplace strategy**:
- **Integration-first** packages minimize adoption friction.
- Start with **one wedge ICP** (marketing agencies recommended) and ship **lighthouse packages**.
- Use **bundles** and **partner loops** for expansion.
- Add a premium “platform” tier later when package breadth and governance justify it.

This GTM theory should drive the realignment of engineering work toward:
1) package registry + install lifecycle
2) execution/logging/observability needed for reliable packages
3) lighthouse packages that prove install-to-value and retention