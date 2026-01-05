defmodule FleetPrompt.Packages do
  @moduledoc """
  Ash domain for package-related resources (Phase 2).

  Packages are global (public schema). Tenant-scoped installs will be added as a
  separate resource in Phase 2/3.
  """

  use Ash.Domain, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
    name("Packages")
  end

  resources do
    resource(FleetPrompt.Packages.Package)
    resource(FleetPrompt.Packages.Review)

    # Phase 2 (next):
    # resource(FleetPrompt.Packages.Installation)
  end
end
