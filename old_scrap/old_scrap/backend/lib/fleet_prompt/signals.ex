defmodule FleetPrompt.Signals do
  @moduledoc """
  Ash domain for **Signals** (Phase 2B).

  Signals are immutable, tenant-scoped facts (persisted events) that represent
  something that *happened* in the system (or was observed from the outside).

  This domain is intentionally created early so it can be added to
  `:ash_domains` without forcing the Signal resource to exist yet.

  Resources will be added in Phase 2B (e.g. `FleetPrompt.Signals.Signal`).
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
    name("Signals")
  end

  resources do
    resource(FleetPrompt.Signals.Signal)
  end
end

# NOTE:
# `FleetPrompt.Directives` has been split into its own file:
# `lib/fleet_prompt/directives.ex`
