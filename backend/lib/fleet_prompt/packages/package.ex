defmodule FleetPrompt.Packages.Package do
  @moduledoc """
  Global marketplace package registry (Phase 2).

  Notes:
  - This resource is *not* multi-tenant. Packages live in the public schema.
  - Tenant-scoped installation tracking lives in a separate resource (Phase 2).
  """

  use Ash.Resource,
    domain: FleetPrompt.Packages,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr
  require Ash.Query

  postgres do
    table("packages")
    repo(FleetPrompt.Repo)
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

    attribute :version, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :long_description, :string do
      public?(true)
    end

    attribute :category, :atom do
      constraints(
        one_of: [
          :operations,
          :customer_service,
          :sales,
          :data,
          :development,
          :marketing,
          :finance,
          :hr
        ]
      )

      public?(true)
    end

    # Publisher metadata
    attribute :author, :string do
      public?(true)
    end

    attribute :author_url, :string do
      public?(true)
    end

    attribute :repository_url, :string do
      public?(true)
    end

    attribute :documentation_url, :string do
      public?(true)
    end

    attribute :license, :string do
      default("MIT")
      public?(true)
    end

    attribute :icon_url, :string do
      public?(true)
    end

    # Pricing
    attribute :pricing_model, :atom do
      constraints(one_of: [:free, :freemium, :paid, :revenue_share])
      default(:free)
      public?(true)
    end

    attribute :pricing_config, :map do
      default(%{})
      public?(true)
    end

    # Requirements
    attribute :min_fleet_prompt_tier, :atom do
      constraints(one_of: [:free, :pro, :enterprise])
      default(:free)
      public?(true)
    end

    attribute :dependencies, {:array, :map} do
      default([])
      public?(true)
    end

    # Package content (registry pointers)
    attribute :package_url, :string do
      public?(true)
    end

    attribute :checksum, :string do
      public?(true)
    end

    # Package includes (for display + install planning)
    attribute :includes, :map do
      default(%{
        "agents" => [],
        "workflows" => [],
        "skills" => [],
        "tools" => []
      })

      public?(true)
    end

    # Stats
    attribute :install_count, :integer do
      default(0)
      public?(true)
    end

    attribute :active_install_count, :integer do
      default(0)
      public?(true)
    end

    attribute :rating_avg, :decimal do
      public?(true)
    end

    attribute :rating_count, :integer do
      default(0)
      public?(true)
    end

    # Flags
    attribute :is_verified, :boolean do
      default(false)
      public?(true)
    end

    attribute :is_featured, :boolean do
      default(false)
      public?(true)
    end

    attribute :is_published, :boolean do
      default(false)
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_name_version, [:name, :version])
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :name,
        :slug,
        :version,
        :description,
        :long_description,
        :category,
        :author,
        :author_url,
        :repository_url,
        :documentation_url,
        :license,
        :icon_url,
        :pricing_model,
        :pricing_config,
        :min_fleet_prompt_tier,
        :dependencies,
        :package_url,
        :checksum,
        :includes,
        :install_count,
        :active_install_count,
        :rating_avg,
        :rating_count,
        :is_verified,
        :is_featured,
        :is_published
      ])
    end

    update :update do
      accept([
        :description,
        :long_description,
        :category,
        :author,
        :author_url,
        :repository_url,
        :documentation_url,
        :license,
        :icon_url,
        :pricing_model,
        :pricing_config,
        :min_fleet_prompt_tier,
        :dependencies,
        :package_url,
        :checksum,
        :includes,
        :is_verified,
        :is_featured,
        :is_published
      ])
    end

    update :increment_installs do
      require_atomic?(false)

      change(fn changeset, _context ->
        current = changeset.data.install_count || 0
        Ash.Changeset.force_change_attribute(changeset, :install_count, current + 1)
      end)
    end

    read :search do
      argument(:query, :string)
      argument(:category, :atom)
      argument(:pricing_model, :atom)
      argument(:tier, :atom)

      prepare(fn query, ctx ->
        args =
          cond do
            is_map(ctx) and Map.has_key?(ctx, :arguments) and is_map(ctx.arguments) ->
              ctx.arguments

            is_map(ctx) and Map.has_key?(ctx, "arguments") and is_map(ctx["arguments"]) ->
              ctx["arguments"]

            true ->
              %{}
          end

        search_term = Map.get(args, :query) || Map.get(args, "query")
        category = Map.get(args, :category) || Map.get(args, "category")
        pricing_model = Map.get(args, :pricing_model) || Map.get(args, "pricing_model")
        tier = Map.get(args, :tier) || Map.get(args, "tier")

        query
        |> filter_by_search(search_term)
        |> filter_by_category(category)
        |> filter_by_pricing(pricing_model)
        |> filter_by_tier(tier)
        |> Ash.Query.filter(expr(is_published == true))
        |> Ash.Query.sort(install_count: :desc)
      end)
    end

    read :featured do
      prepare(fn query, _ctx ->
        query
        |> Ash.Query.filter(expr(is_featured == true and is_published == true))
        |> Ash.Query.limit(6)
      end)
    end

    read :by_slug do
      argument(:slug, :string, allow_nil?: false)
      get?(true)

      filter(expr(slug == ^arg(:slug)))
    end
  end

  calculations do
    calculate(:can_install, :boolean, expr(is_published == true))
  end

  admin do
    table_columns([
      :name,
      :slug,
      :version,
      :category,
      :pricing_model,
      :min_fleet_prompt_tier,
      :install_count,
      :rating_avg,
      :is_verified,
      :is_featured,
      :is_published
    ])
  end

  # Filtering helpers (used by the :search action)

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query

  defp filter_by_search(query, search_term) when is_binary(search_term) do
    term = String.trim(search_term)

    if term == "" do
      query
    else
      Ash.Query.filter(
        query,
        expr(
          contains(name, ^term) or
            contains(description, ^term)
        )
      )
    end
  end

  defp filter_by_search(query, _), do: query

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, ""), do: query

  defp filter_by_category(query, category),
    do: Ash.Query.filter(query, expr(category == ^category))

  defp filter_by_pricing(query, nil), do: query
  defp filter_by_pricing(query, ""), do: query

  defp filter_by_pricing(query, pricing),
    do: Ash.Query.filter(query, expr(pricing_model == ^pricing))

  defp filter_by_tier(query, nil), do: query
  defp filter_by_tier(query, ""), do: query

  defp filter_by_tier(query, tier) do
    available_tiers =
      case tier do
        :free -> [:free]
        :pro -> [:free, :pro]
        :enterprise -> [:free, :pro, :enterprise]
        other when is_binary(other) -> filter_by_tier(query, String.to_existing_atom(other))
        _ -> nil
      end

    case available_tiers do
      nil ->
        query

      tiers ->
        Ash.Query.filter(query, expr(min_fleet_prompt_tier in ^tiers))
    end
  rescue
    ArgumentError ->
      query
  end
end
