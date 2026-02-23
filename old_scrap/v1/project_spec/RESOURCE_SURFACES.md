# FleetPrompt Resource Surfaces (`.fleetprompt/`)

FleetPrompt’s primary input is the `.fleetprompt/` folder inside a project repo.

Goal: OpenSentience Core can index these resources **without executing code**.

## 1) Folder layout

- `.fleetprompt/config.toml`
- `.fleetprompt/skills/`
- `.fleetprompt/workflows/`
- `.fleetprompt/graphonomous/` (optional)
- `.fleetprompt/delegatic/` (optional)
- `.fleetprompt/a2a/` (optional)

## 2) `config.toml` schema (portfolio baseline)

See `opensentience.org/project_spec/portfolio-integration.md` for the baseline example.

FleetPrompt must support at least:

- `[project] name, version`
- `[fleetprompt] enabled`
- `[[skills]] id, name, entry, permissions`
- `[[workflows]] id, name, entry, triggers`

## 3) Skills

A skill is the smallest reusable unit that can be exposed as a tool.

### Skill entry types (MVP decision point)

You can implement MVP skills in one of these ways:

- **Elixir script skill**: `skills/my_skill.exs`
- **Elixir module skill**: referenced via module/function name
- **External command skill**: a command with strict allowlisting (higher risk)

The spec intentionally allows flexibility, but whichever type is chosen must be:

- discoverable via `config.toml` and/or `skills/` index
- executable with explicit permissions
- auditable

## 4) Workflows

A workflow is a higher-level run definition that sequences skills and external tool calls.

MVP recommendation:

- YAML workflow definition (static schema; easy to validate)

Future option:

- a workflow DSL that compiles into the YAML form

## 5) Validation rules

FleetPrompt must validate:

- required fields are present
- file paths are within the project (no `../` escape)
- referenced skill/workflow files exist
- permissions are declared and use known prefixes
- triggers are syntactically valid (even if not executed in MVP)
