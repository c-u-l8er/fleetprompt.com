defmodule FleetPrompt.Accounts.Organization do
  use Ash.Resource,
    domain: FleetPrompt.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table("organizations")
    repo(FleetPrompt.Repo)

    # Automatic tenant schema management (schema-per-tenant)
    manage_tenant do
      template(["org_", :slug])
      create?(true)
      update?(false)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :tier, :atom do
      constraints(one_of: [:free, :pro, :enterprise])
      default(:free)
      public?(true)
    end

    attribute :billing_status, :atom do
      constraints(one_of: [:active, :suspended, :trial, :canceled])
      default(:trial)
      public?(true)
    end

    # Usage limits (derived from tier)
    attribute :monthly_token_limit, :integer do
      default(100_000)
      public?(true)
    end

    attribute :agent_limit, :integer do
      default(3)
      public?(true)
    end

    attribute :workflow_limit, :integer do
      default(0)
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :slug, :tier])

      change(fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :tier) || :free
        limits = calculate_tier_limits(tier)

        changeset
        |> Ash.Changeset.force_change_attribute(:monthly_token_limit, limits.tokens)
        |> Ash.Changeset.force_change_attribute(:agent_limit, limits.agents)
        |> Ash.Changeset.force_change_attribute(:workflow_limit, limits.workflows)
      end)
    end

    update :update do
      accept([:name, :tier, :billing_status])
    end

    update :upgrade_tier do
      accept([:tier])
      require_atomic?(false)

      change(fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :tier) || :free
        limits = calculate_tier_limits(tier)

        changeset
        |> Ash.Changeset.force_change_attribute(:monthly_token_limit, limits.tokens)
        |> Ash.Changeset.force_change_attribute(:agent_limit, limits.agents)
        |> Ash.Changeset.force_change_attribute(:workflow_limit, limits.workflows)
      end)
    end
  end

  relationships do
    has_many(:users, FleetPrompt.Accounts.User)
  end

  admin do
    table_columns([:name, :slug, :tier, :billing_status])
  end

  defp calculate_tier_limits(:free), do: %{tokens: 100_000, agents: 3, workflows: 0}
  defp calculate_tier_limits(:pro), do: %{tokens: 1_000_000, agents: 999, workflows: 10}
  defp calculate_tier_limits(:enterprise), do: %{tokens: 999_999_999, agents: 999, workflows: 999}
  defp calculate_tier_limits(_), do: %{tokens: 100_000, agents: 3, workflows: 0}

  # Allows passing an Organization struct to `Ash.Changeset.set_tenant/2`
  # when working with schema-per-tenant resources.
  defimpl Ash.ToTenant do
    def to_tenant(%{slug: slug}, _resource) when is_binary(slug), do: "org_#{slug}"
    def to_tenant(_org, _resource), do: nil
  end
end
