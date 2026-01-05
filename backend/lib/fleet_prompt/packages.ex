defmodule FleetPrompt.Packages do
  @moduledoc """
  Ash domain placeholder for package-related resources.

  This module exists so `FleetPrompt.Packages` can be referenced in configuration
  (e.g. `:ash_domains`) before Phase 2 resources are implemented.
  """

  use Ash.Domain

  resources do
    # Phase 2 will register resources here, e.g.:
    # resource FleetPrompt.Packages.Package
    # resource FleetPrompt.Packages.Installation
    # resource FleetPrompt.Packages.Review
  end
end
