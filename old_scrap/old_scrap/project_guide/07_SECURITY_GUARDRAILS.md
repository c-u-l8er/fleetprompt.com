# Security guardrails (FleetPrompt stance)

This guide translates FleetPrompt’s security posture into concrete engineering guardrails for **agents, tools, packages, signals, directives, and integrations**.

Canonical security strategy:
- [`project_theory/SECURITY_AND_CREDENTIALS.md`](project_theory/SECURITY_AND_CREDENTIALS.md:1)

## 0) Threat model summary (what we defend)

1. **Cross-tenant access** (existential)
2. **Secret disclosure** (tokens, webhook secrets, credentials)
3. **Webhook spoofing / replay**
4. **Prompt injection causing unintended side effects**
5. **Abuse and cost explosions** (LLM, integrations)

## 1) Non-negotiable invariants

### 1.1 Tenant context is derived server-side

Tenant is not chosen by the client for privileged operations.

- Browser UI tenant selection: membership-gated in [`FleetPromptWeb.Plugs.FetchOrgContext`](backend/lib/fleet_prompt_web/plugs/fetch_org_context.ex:1)
- Admin tenant selection is pinned to the signed-in user’s org when possible in [`FleetPromptWeb.Plugs.AdminTenant`](backend/lib/fleet_prompt_web/plugs/admin_tenant.ex:11)

Rule of thumb:
- controllers and jobs must be explicit about `tenant` and must not accept arbitrary tenant override parameters.

### 1.2 No secrets in Signals, Directives, logs

Signals are durable and replayable. Treat them like logs.

- SignalBus explicitly documents this rule: [`FleetPrompt.Signals.SignalBus`](backend/lib/fleet_prompt/signals/signal_bus.ex:1)

Guardrail:
- never include `access_token`, `refresh_token`, `authorization`, `api_key`, cookies, webhook secrets, or SMTP/IMAP credentials in:
  - signal payloads
  - directive payloads
  - execution logs

Instead:
- store secrets in a dedicated encrypted credential resource (planned; see [`SECURITY_AND_CREDENTIALS.md`](project_theory/SECURITY_AND_CREDENTIALS.md:118))
- reference credential ids in signals/directives

### 1.3 Side effects require explicit intent (directives)

Any operation that is:
- retryable
- externally impactful
- safety-sensitive

…should be executed as a directive, not as an implicit write.

This is already enforced for:
- package installs and uninstalls via [`FleetPrompt.Jobs.DirectiveRunner`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1)
- forum moderation directives (lock/hide/delete) via [`FleetPrompt.Jobs.DirectiveRunner`](backend/lib/fleet_prompt/jobs/directive_runner.ex:1)

## 2) Chat and tool calling guardrails

### 2.1 Current state

Chat supports tool calling and some tools can directly mutate tenant state.

- Tool execution: [`FleetPrompt.AI.Tools.execute/4`](backend/lib/fleet_prompt/ai/tools.ex:105)

### 2.2 Required evolution

As tools expand beyond forums:

- mutating tools should become **directive request tools**
- the directive runner performs the actual mutation
- the tool returns a directive id + a user-safe status

This is both a trust requirement and a security requirement.

### 2.3 Prompt injection posture

Prompt injection is expected. Your defense is architectural:

- do not let model output become direct side effects
- require explicit, typed, validated actions
- require explicit user confirmation for high-impact actions

## 3) Authorization and role gating

### 3.1 Admin surfaces require org-admin roles

- Org-admin gating plug: [`FleetPromptWeb.Plugs.RequireOrgAdmin`](backend/lib/fleet_prompt_web/plugs/require_org_admin.ex:1)

Baseline rule:
- only org roles `:owner` and `:admin` should be able to request privileged directives:
  - install/upgrade/uninstall
  - integration credential actions
  - moderation actions that hide/delete

### 3.2 Member safe actions

Members can be allowed to:
- create threads/posts
- view audit trails

But agent actions and moderation actions should remain directive-backed and role-gated.

## 4) Integration and credential guardrails

### 4.1 Store credentials in tenant scope

From the security strategy:
- default to tenant-scoped encrypted credential records
- never store secrets in plain text

Reference: [`SECURITY_AND_CREDENTIALS.md`](project_theory/SECURITY_AND_CREDENTIALS.md:118)

### 4.2 Webhook ingestion pattern

Inbound webhooks must:
1. verify signature
2. dedupe using provider event ids
3. emit a persisted signal (source + source_event_id)
4. enqueue durable processing

Reference: [`SECURITY_AND_CREDENTIALS.md`](project_theory/SECURITY_AND_CREDENTIALS.md:244)

## 5) Dedupe and idempotency rules (safety and security)

- Signals: use `dedupe_key` when a source can redeliver/retry.
- Directives: use `idempotency_key` for any action a user might click twice.

Reference implementation:
- SignalBus dedupe behavior: [`FleetPrompt.Signals.SignalBus`](backend/lib/fleet_prompt/signals/signal_bus.ex:46)

Operational implication:
- replay is only safe when handlers and directives are idempotent.

## 6) Operational controls (abuse and cost)

Minimum controls to add as platform scope grows:

- per-tenant rate limiting for high-cost operations
- per-tenant quotas for LLM usage
- tool allowlists per package installation (capability-based security)
- kill-switch directives to disable packages/integrations quickly

Reference: rate limiting and abuse controls guidance in [`SECURITY_AND_CREDENTIALS.md`](project_theory/SECURITY_AND_CREDENTIALS.md:326)

## 7) Security checklist for adding a new agent/tool/workflow

When adding anything that can mutate state or trigger effects:

1. Tenant context is explicit and cannot be spoofed.
2. Side effects go through directives.
3. All signals are JSON-safe and secret-free.
4. Idempotency keys exist (directive) and dedupe keys exist (signal) where needed.
5. Role gating is explicit for privileged actions.
6. Logs are structured and redacted.
7. There is an audit trail UI path (or at least queryability) for support.

For templates, see:
- [`project_blueprints/BLUEPRINT_TOOL.md`](project_blueprints/BLUEPRINT_TOOL.md:1)
- [`project_blueprints/BLUEPRINT_DIRECTIVE_HANDLER.md`](project_blueprints/BLUEPRINT_DIRECTIVE_HANDLER.md:1)
- [`project_blueprints/BLUEPRINT_SIGNAL_HANDLER.md`](project_blueprints/BLUEPRINT_SIGNAL_HANDLER.md:1)
