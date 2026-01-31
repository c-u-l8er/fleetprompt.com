# FleetPrompt Test Plan

These tests exist to preserve the “hidden gems” from legacy FleetPrompt while changing architecture.

## 1) Resource validation

- invalid TOML
- missing required fields
- path traversal attempts (`../`)
- unknown permission prefixes

## 2) Tool registration

- tools derived from skills/workflows are stable
- schema validation rejects bad inputs

## 3) Execution semantics

- idempotency key returns existing result
- cancellation transitions the execution record correctly
- logs are structured and secret-free

## 4) Security

- secret redaction: known keys must not persist
- deny-by-default: unknown tools cannot run
- side effects require explicit directives (unit test with a “side effect” skill)

## 5) Audit

- execution lifecycle signals emitted with correct correlation ids
- replay safety checks (idempotent handlers)
