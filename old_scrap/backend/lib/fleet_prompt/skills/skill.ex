defmodule FleetPrompt.Skills.Skill do
  use Ash.Resource,
    domain: FleetPrompt.Skills,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table("skills")
    repo(FleetPrompt.Repo)
  end

  # Skills are global (not multi-tenant) in Phase 1.

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

    attribute :description, :string do
      public?(true)
    end

    attribute :category, :atom do
      constraints(one_of: [:research, :coding, :data_analysis, :communication, :operations])
      public?(true)
    end

    attribute :tier_required, :atom do
      constraints(one_of: [:free, :pro, :enterprise])
      default(:free)
      public?(true)
    end

    attribute :system_prompt_enhancement, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :tools, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :is_official, :boolean do
      default(false)
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
      accept([
        :name,
        :slug,
        :description,
        :category,
        :tier_required,
        :system_prompt_enhancement,
        :tools,
        :is_official
      ])
    end

    update :update do
      accept([
        :name,
        :slug,
        :description,
        :category,
        :tier_required,
        :system_prompt_enhancement,
        :tools,
        :is_official
      ])
    end
  end

  admin do
    table_columns([:name, :slug, :category, :tier_required, :is_official])
  end
end
