defmodule FleetPrompt.Agents do
  @moduledoc """
  Ash domain for agent-related resources and business logic.

  In Phase 1, this domain registers the multi-tenant `FleetPrompt.Agents.Agent` resource.
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
    name("Agents")
  end

  resources do
    resource(FleetPrompt.Agents.Agent)
    resource(FleetPrompt.Agents.Execution)
    resource(FleetPrompt.Agents.ExecutionLog)
  end
end
