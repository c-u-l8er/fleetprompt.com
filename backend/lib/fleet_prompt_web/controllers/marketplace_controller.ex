defmodule FleetPromptWeb.MarketplaceController do
  @moduledoc """
  Marketplace pages rendered via Inertia.

  This controller is written to be forward-compatible with Phase 2 (Packages),
  while still keeping `/marketplace` functional if the package system hasn't
  been implemented yet.

  Current behavior:
  - If `FleetPrompt.Packages.Package` exists, it will try to load packages via Ash reads.
  - If it does not exist (or reads fail), it falls back to an empty marketplace payload
    and renders the existing `Marketplace` Inertia page.
  """

  use FleetPromptWeb, :controller
  require Logger

  @category_map %{
    "operations" => :operations,
    "customer_service" => :customer_service,
    "sales" => :sales,
    "data" => :data,
    "development" => :development,
    "marketing" => :marketing,
    "finance" => :finance,
    "hr" => :hr
  }

  @pricing_map %{
    "free" => :free,
    "freemium" => :freemium,
    "paid" => :paid,
    "revenue_share" => :revenue_share
  }

  @tier_map %{
    "free" => :free,
    "pro" => :pro,
    "enterprise" => :enterprise
  }

  # GET /marketplace
  def index(conn, params) do
    q = normalize_blank(params["q"])
    category = normalize_mapped(params["category"], @category_map)
    pricing_model = normalize_mapped(params["pricing"], @pricing_map)
    tier = normalize_mapped(params["tier"], @tier_map)

    {packages, featured} =
      case packages_available?() do
        true ->
          {
            load_packages(q, category, pricing_model, tier),
            load_featured()
          }

        false ->
          {[], []}
      end

    # Keep props stable; the current `Marketplace.svelte` will safely ignore extra props.
    render_inertia(conn, "Marketplace", %{
      title: "Marketplace",
      subtitle: "Browse installable packages (agents, workflows, skills). Coming soon.",
      packages: serialize_packages(packages),
      featured: serialize_packages(featured),
      filters: %{
        query: q,
        category: params["category"],
        pricing: params["pricing"],
        tier: params["tier"]
      }
    })
  end

  # (Future) GET /marketplace/:slug
  #
  # NOTE: You likely don't have a `Marketplace/Show` page yet; keep this action
  # around for Phase 2 routing, but it won't be used until the route + page exist.
  def show(conn, %{"slug" => slug}) do
    if packages_available?() do
      case load_package_by_slug(slug) do
        nil ->
          conn
          |> put_status(:not_found)
          |> render_inertia("Marketplace", %{
            title: "Marketplace",
            subtitle: "Package not found.",
            packages: [],
            featured: [],
            filters: %{}
          })

        pkg ->
          # Render the same Marketplace page for now; Phase 2 can switch to `Marketplace/Show`.
          render_inertia(conn, "Marketplace", %{
            title: "Marketplace",
            subtitle: "Package details (placeholder until Phase 2 UI lands).",
            package: serialize_package_detail(pkg),
            packages: [],
            featured: [],
            filters: %{}
          })
      end
    else
      render_inertia(conn, "Marketplace", %{
        title: "Marketplace",
        subtitle: "Package system not implemented yet.",
        packages: [],
        featured: [],
        filters: %{}
      })
    end
  end

  # -----------------------
  # Ash loading (optional)
  # -----------------------

  defp packages_available? do
    Code.ensure_loaded?(FleetPrompt.Packages.Package)
  end

  defp load_packages(q, category, pricing_model, tier) do
    args = %{
      query: q,
      category: category,
      pricing_model: pricing_model,
      tier: tier
    }

    safe_read(
      fn ->
        FleetPrompt.Packages.Package
        |> Ash.Query.for_read(:search, args)
        |> Ash.read!()
      end,
      default: []
    )
  end

  defp load_featured do
    safe_read(
      fn ->
        FleetPrompt.Packages.Package
        |> Ash.Query.for_read(:featured)
        |> Ash.read!()
      end,
      default: []
    )
  end

  defp load_package_by_slug(slug) do
    safe_read(
      fn ->
        FleetPrompt.Packages.Package
        |> Ash.Query.for_read(:by_slug, %{slug: slug})
        |> Ash.read_one!()
      end,
      default: nil
    )
  end

  defp safe_read(fun, opts) when is_function(fun, 0) do
    default = Keyword.get(opts, :default)

    try do
      fun.()
    rescue
      err ->
        Logger.warning(
          "[MarketplaceController] Falling back (Ash read failed): #{Exception.message(err)}"
        )

        default
    catch
      kind, reason ->
        Logger.warning(
          "[MarketplaceController] Falling back (Ash read failed): #{inspect(kind)} #{inspect(reason)}"
        )

        default
    end
  end

  # -----------------------
  # Serialization helpers
  # -----------------------

  defp serialize_packages(packages) when is_list(packages) do
    Enum.map(packages, &serialize_package/1)
  end

  defp serialize_package(pkg) do
    %{
      id: Map.get(pkg, :id),
      name: Map.get(pkg, :name),
      slug: Map.get(pkg, :slug),
      description: Map.get(pkg, :description),
      category: Map.get(pkg, :category),
      icon_url: Map.get(pkg, :icon_url),
      pricing_model: Map.get(pkg, :pricing_model),
      pricing_config: Map.get(pkg, :pricing_config) || %{},
      install_count: Map.get(pkg, :install_count) || 0,
      rating_avg: serialize_decimal(Map.get(pkg, :rating_avg)),
      rating_count: Map.get(pkg, :rating_count) || 0,
      is_verified: Map.get(pkg, :is_verified) || false,
      is_featured: Map.get(pkg, :is_featured) || false
    }
  end

  defp serialize_package_detail(pkg) do
    Map.merge(serialize_package(pkg), %{
      long_description: Map.get(pkg, :long_description),
      author: Map.get(pkg, :author),
      author_url: Map.get(pkg, :author_url),
      repository_url: Map.get(pkg, :repository_url),
      documentation_url: Map.get(pkg, :documentation_url),
      license: Map.get(pkg, :license),
      version: Map.get(pkg, :version),
      includes: Map.get(pkg, :includes) || %{},
      dependencies: Map.get(pkg, :dependencies) || [],
      min_fleet_prompt_tier: Map.get(pkg, :min_fleet_prompt_tier)
    })
  end

  defp serialize_decimal(nil), do: nil
  defp serialize_decimal(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp serialize_decimal(other), do: other

  # -----------------------
  # Param normalization
  # -----------------------

  defp normalize_blank(nil), do: nil

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_mapped(nil, _map), do: nil

  defp normalize_mapped(value, map) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> nil
      true -> Map.get(map, value)
    end
  end
end
