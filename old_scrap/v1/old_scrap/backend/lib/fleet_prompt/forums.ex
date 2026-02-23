defmodule FleetPrompt.Forums do
  @moduledoc """
  Ash domain for Forums.

  This domain is introduced as part of the Forums-first lighthouse work (Phase 2C)
  and becomes the long-term home for the Agent-Native Forum track (Phase 6).

  Notes:
  - Forums data is intended to be **tenant-scoped** (schema-per-tenant via `multitenancy :context`)
    like `FleetPrompt.Agents.Agent`.
  - The concrete forum resources (`Category`, `Thread`, `Post`, etc.) will be added
    incrementally. This domain is safe to ship before those resources exist.

  Once resources exist, they should be registered under `resources do ... end`
  so they are discoverable by Ash and AshAdmin.
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
    name("Forums")
  end

  resources do
    resource(FleetPrompt.Forums.Category)
    resource(FleetPrompt.Forums.Thread)
    resource(FleetPrompt.Forums.Post)
  end
end
