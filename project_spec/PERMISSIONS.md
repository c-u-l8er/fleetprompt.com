# FleetPrompt Permissions Model

FleetPrompt is an OpenSentience Agent; permissions are portfolio-wide.

## 1) Layers of permissions

1. **Agent-level permissions** (requested in `opensentience.agent.json`, approved on Enable)
2. **Skill/workflow permissions** (declared in `.fleetprompt/config.toml`)
3. **Per-invocation constraints** (validated inputs + allowlists)

## 2) Permission formats

Use explicit, capability-like strings (see portfolio standard):

- `filesystem:read:<glob>`
- `filesystem:write:<glob>`
- `network:egress:<host-or-tag>`
- `a2a:publish:<topic>` / `a2a:subscribe:<topic>`

## 3) Enforcement points

- At tool registration time: FleetPrompt should not register tools that have undeclared permissions.
- At tool execution time: FleetPrompt must check that:
  - permissions are approved for this agent
  - permissions are allowed for this specific skill

## 4) Redaction

Even with correct permissions:

- redact sensitive values in logs (best-effort)
- block known secret keys (`api_key`, `token`, `authorization`, etc.) from being persisted
