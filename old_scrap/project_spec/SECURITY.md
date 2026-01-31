# FleetPrompt Security Guardrails

This is FleetPrompt’s reimplementation security stance, derived from legacy FleetPrompt.

## 1) Prompt injection posture

Assume prompt injection will happen.

Defense is architectural:

- model/tool output must not directly cause side effects
- side effects are executed via explicit, typed directives
- require user confirmation for high-impact actions

## 2) Secrets

- Never put secrets in signals, directives, or logs.
- Store secrets in a dedicated encrypted store and reference them by id.

## 3) Permissions enforcement

- Every tool invocation must be permission-checked.
- Prefer deny-by-default.

## 4) Drive-by action protection

FleetPrompt should not expose network endpoints by default.

If FleetPrompt does expose any local web surface later:

- bind to `127.0.0.1`
- require an auth token
- enforce CSRF

## 5) Cost and abuse controls

As soon as FleetPrompt can trigger LLM or network work:

- implement quotas/rate limits at the Core boundary
- log usage metrics in an audit-safe manner
