# FleetPrompt Interfaces (Draft)

This file defines the stable interface surface FleetPrompt should expose when running as an OpenSentience Agent.

## Input surfaces

- Project resources: `.fleetprompt/`
- Optional: remote skill/workflow registries (later)

## Tools (proposed)

### Catalog / discovery

- `fp_validate_project_resources({"project_path": string})`
- `fp_list_skills({"project_path"?: string})`
- `fp_describe_skill({"skill_id": string})`
- `fp_list_workflows({"project_path"?: string})`
- `fp_describe_workflow({"workflow_id": string})`

### Execution

- `fp_run_skill({"skill_id": string, "inputs": object, "idempotency_key"?: string})`
- `fp_run_workflow({"workflow_id": string, "inputs": object, "idempotency_key"?: string})`
- `fp_cancel_execution({"execution_id": string})`

## Signals (facts)

FleetPrompt should emit signals for:

- `fleetprompt.skill.discovered`
- `fleetprompt.workflow.discovered`
- `fleetprompt.execution.started`
- `fleetprompt.execution.succeeded`
- `fleetprompt.execution.failed`

Signals must be secret-free.

## Directives (intent)

FleetPrompt should request directives for side effects, such as:

- `fleetprompt.execution.run`
- `fleetprompt.execution.cancel`

If execution causes external effects (deploy, email, etc), those effects must be explicit directives.
