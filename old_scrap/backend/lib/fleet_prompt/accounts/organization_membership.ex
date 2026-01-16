defmodule FleetPrompt.Accounts.OrganizationMembership do
  @moduledoc """
  Join resource that grants a `User` access to an `Organization` with a per-org role.

  Why this exists:
  - A user can belong to multiple organizations.
  - Tenant selection (schema-per-tenant) must be restricted to organizations the user
    is a member of.
  - Authorization can be enforced via membership role (e.g. only `:owner`/`:admin`
    should access admin surfaces).

  Notes:
  - This resource is stored in the **public** schema (not tenant-scoped).
  - Tenant-specific resources (e.g. Agents) should use the selected org's tenant
    (`"org_<slug>"`) and should pass the user as the `actor`.
  """

  use Ash.Resource,
    domain: FleetPrompt.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table("organization_memberships")
    repo(FleetPrompt.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :role, :atom do
      allow_nil?(false)
      constraints(one_of: [:owner, :admin, :member])
      default(:member)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:active, :invited, :disabled])
      default(:active)
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :user, FleetPrompt.Accounts.User do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :organization, FleetPrompt.Accounts.Organization do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    # Prevent duplicate memberships for the same user/org pair.
    identity(:unique_user_org, [:user_id, :organization_id])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:user_id, :organization_id, :role, :status])
    end

    update :update do
      accept([:role, :status])
    end
  end

  admin do
    table_columns([:user_id, :organization_id, :role, :status, :inserted_at])
  end
end
