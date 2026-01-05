defmodule FleetPrompt.Accounts do
  @moduledoc """
  Ash domain for account-related resources (organizations, users, etc.).
  """

  use Ash.Domain,
    extensions: [AshAdmin.Domain]

  resources do
    resource(FleetPrompt.Accounts.Organization)
    resource(FleetPrompt.Accounts.User)
  end

  admin do
    show?(true)
  end
end
