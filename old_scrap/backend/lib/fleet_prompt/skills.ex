defmodule FleetPrompt.Skills do
  @moduledoc """
  Ash domain for the global Skills catalog.
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource(FleetPrompt.Skills.Skill)
  end
end
