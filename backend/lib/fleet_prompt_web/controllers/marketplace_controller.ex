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

  alias FleetPrompt.Packages.{Installation, Package}
  alias FleetPrompt.Jobs.PackageInstaller

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
    tenant = conn.assigns[:ash_tenant]

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

    installation_status =
      cond do
        is_binary(tenant) and String.trim(tenant) != "" and Code.ensure_loaded?(Installation) ->
          load_installation_status_by_slug(String.trim(tenant))

        true ->
          %{}
      end

    # Backwards-compatible convenience list (used by older UI code paths)
    installed_slugs =
      installation_status
      |> Enum.filter(fn {_slug, v} ->
        Map.get(v, :enabled) == true and Map.get(v, :status) == :installed
      end)
      |> Enum.map(fn {slug, _} -> slug end)

    # Keep props stable; the current `Marketplace.svelte` will safely ignore extra props.
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Marketplace", %{
      title: "Marketplace",
      subtitle: "Browse installable packages (agents, workflows, skills). Coming soon.",
      packages: serialize_packages(packages),
      featured: serialize_packages(featured),
      installed_slugs: installed_slugs,
      installation_status: installation_status,
      filters: %{
        query: q,
        category: params["category"],
        pricing: params["pricing"],
        tier: params["tier"]
      }
    })
  end

  # GET /marketplace/installations/status
  #
  # Lightweight polling endpoint for Marketplace UI install status.
  # Returns a JSON map keyed by package slug with the current tenant's installation state.
  def installation_status(conn, _params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    org = conn.assigns[:current_organization]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      is_nil(org) ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "organization context is missing"})

      !is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      !Code.ensure_loaded?(Installation) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "installations are not implemented yet"})

      true ->
        # IMPORTANT:
        # `load_installation_status_by_slug/1` is intentionally defensive and may return `%{}` on errors.
        # For the polling endpoint, we want a *clear* signal when tenant migrations haven't been applied.
        case Ash.read(Installation, tenant: tenant) do
          {:ok, _installations} ->
            status =
              case load_installation_status_by_slug(tenant) do
                m when is_map(m) -> m
                _ -> %{}
              end

            json(conn, %{ok: true, tenant: tenant, installation_status: status})

          {:error, err} ->
            msg = Exception.message(err)

            if tenant_installations_table_missing?(msg) do
              conn
              |> put_status(:conflict)
              |> json(%{
                ok: false,
                error: normalize_install_error(:tenant_installations_table_missing)
              })
            else
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{ok: false, error: msg})
            end
        end
    end
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
          |> FleetPromptWeb.InertiaHelpers.render_inertia("Marketplace", %{
            title: "Marketplace",
            subtitle: "Package not found.",
            packages: [],
            featured: [],
            filters: %{}
          })

        pkg ->
          # Render the same Marketplace page for now; Phase 2 can switch to `Marketplace/Show`.
          FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Marketplace", %{
            title: "Marketplace",
            subtitle: "Package details (placeholder until Phase 2 UI lands).",
            package: serialize_package_detail(pkg),
            packages: [],
            featured: [],
            filters: %{}
          })
      end
    else
      FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Marketplace", %{
        title: "Marketplace",
        subtitle: "Package system not implemented yet.",
        packages: [],
        featured: [],
        filters: %{}
      })
    end
  end

  # POST /marketplace/install
  #
  # Expects JSON (or form) params:
  # - slug (required)
  # - version (optional; if provided, must match the package registry version)
  # - idempotency_key (optional; recommended when called from a directive runner)
  # - config (optional map; package-defined config)
  #
  # Response: JSON with `{ok, installation_id, status, tenant, package}`
  def install(conn, params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    org = conn.assigns[:current_organization]

    slug =
      params["slug"] ||
        params["package_slug"] ||
        params["id"]

    requested_version =
      params["version"] ||
        params["package_version"]

    idempotency_key = params["idempotency_key"]
    config = params["config"] || %{}

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      is_nil(org) ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "organization context is missing"})

      !is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      !is_binary(slug) or String.trim(slug) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "missing required param: slug"})

      !packages_available?() ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "package system not implemented yet"})

      !Code.ensure_loaded?(Installation) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "installations are not implemented yet"})

      !Code.ensure_loaded?(PackageInstaller) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "package installer job is not implemented yet"})

      true ->
        slug = String.trim(slug)

        with %Package{} = pkg <- load_package_by_slug(slug),
             :ok <- ensure_version_matches(pkg, requested_version),
             :ok <- ensure_package_installable(pkg, org),
             {:ok, installation} <-
               get_or_create_installation(pkg, tenant, user, config, idempotency_key),
             {:ok, enqueue_status} <- maybe_enqueue_install_job(installation, tenant) do
          json(conn, %{
            ok: true,
            installation_id: installation.id,
            status: installation.status,
            enqueued: enqueue_status == :enqueued,
            tenant: tenant,
            package: %{
              slug: pkg.slug,
              version: pkg.version
            }
          })
        else
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{ok: false, error: "package not found"})

          {:error, :not_published} ->
            # Hide unpublished packages by default
            conn
            |> put_status(:not_found)
            |> json(%{ok: false, error: "package not available"})

          {:error, {:tier_insufficient, required, current}} ->
            conn
            |> put_status(:forbidden)
            |> json(%{
              ok: false,
              error: "organization tier too low to install this package",
              required_tier: required,
              current_tier: current
            })

          {:error, :tenant_installations_table_missing} ->
            conn
            |> put_status(:conflict)
            |> json(%{
              ok: false,
              error: normalize_install_error(:tenant_installations_table_missing)
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{ok: false, error: normalize_install_error(reason)})

          {:version_mismatch, expected, got} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              ok: false,
              error: "package version mismatch",
              expected_version: expected,
              requested_version: got
            })
        end
    end
  end

  defp ensure_version_matches(_pkg, nil), do: :ok
  defp ensure_version_matches(_pkg, ""), do: :ok

  defp ensure_version_matches(%Package{} = pkg, requested_version)
       when is_binary(requested_version) do
    requested_version = String.trim(requested_version)

    if requested_version == "" do
      :ok
    else
      if to_string(pkg.version) == requested_version do
        :ok
      else
        {:version_mismatch, to_string(pkg.version), requested_version}
      end
    end
  end

  defp ensure_package_installable(%Package{} = pkg, org) do
    required_tier = Map.get(pkg, :min_fleet_prompt_tier)
    org_tier = Map.get(org, :tier)

    cond do
      Map.get(pkg, :is_published) != true ->
        {:error, :not_published}

      tier_allows?(org_tier, required_tier) != true ->
        {:error, {:tier_insufficient, required_tier, org_tier}}

      true ->
        :ok
    end
  end

  defp tier_allows?(org_tier, required_tier) do
    tier_rank(normalize_tier(org_tier)) >= tier_rank(normalize_tier(required_tier))
  end

  defp normalize_tier(tier) when is_atom(tier), do: tier

  defp normalize_tier(tier) when is_binary(tier) do
    case String.trim(tier) do
      "free" -> :free
      "pro" -> :pro
      "enterprise" -> :enterprise
      _ -> :free
    end
  end

  defp normalize_tier(_), do: :free

  defp tier_rank(:free), do: 0
  defp tier_rank(:pro), do: 1
  defp tier_rank(:enterprise), do: 2
  defp tier_rank(_), do: 0

  defp get_or_create_installation(%Package{} = pkg, tenant, user, config, idempotency_key) do
    existing_query =
      Installation
      |> Ash.Query.for_read(:by_slug, %{package_slug: pkg.slug})

    case Ash.read_one(existing_query, tenant: tenant) do
      {:ok, %Installation{} = existing} ->
        {:ok, existing}

      {:ok, nil} ->
        Installation
        |> Ash.Changeset.for_create(:request_install, %{
          package_slug: pkg.slug,
          package_version: pkg.version,
          package_name: pkg.name,
          installed_by_user_id: user.id,
          config: config || %{},
          idempotency_key: idempotency_key
        })
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.create()

      {:error, err} ->
        # Common dev-time failure: tenant schema exists, but tenant migrations for
        # `package_installations` haven't been applied yet.
        msg = Exception.message(err)

        if tenant_installations_table_missing?(msg) do
          {:error, :tenant_installations_table_missing}
        else
          {:error, err}
        end
    end
  end

  # Avoid re-enqueueing when a package is already installed or already installing.
  defp maybe_enqueue_install_job(%Installation{} = installation, tenant) do
    case installation.status do
      :installed -> {:ok, :skipped}
      :installing -> {:ok, :skipped}
      :disabled -> {:ok, :skipped}
      _ -> do_enqueue_install_job(installation.id, tenant)
    end
  end

  defp do_enqueue_install_job(installation_id, tenant) do
    case enqueue_install_job(installation_id, tenant) do
      {:ok, _job} -> {:ok, :enqueued}
      {:error, err} -> {:error, err}
    end
  end

  defp enqueue_install_job(installation_id, tenant) do
    job =
      PackageInstaller.new(%{
        "installation_id" => installation_id,
        "tenant" => tenant
      })

    Oban.insert(job)
  end

  defp normalize_install_error(:tenant_installations_table_missing) do
    "This organization tenant schema is missing the `package_installations` table. " <>
      "Run tenant migrations for this org (or recreate the org schema in dev), then retry."
  end

  defp normalize_install_error(%{__exception__: true} = err) do
    msg = Exception.message(err)

    if tenant_installations_table_missing?(msg) do
      normalize_install_error(:tenant_installations_table_missing)
    else
      msg
    end
  end

  defp normalize_install_error(err) when is_binary(err) do
    if tenant_installations_table_missing?(err) do
      normalize_install_error(:tenant_installations_table_missing)
    else
      err
    end
  end

  defp normalize_install_error(err) do
    msg = inspect(err)

    if tenant_installations_table_missing?(msg) do
      normalize_install_error(:tenant_installations_table_missing)
    else
      msg
    end
  end

  defp tenant_installations_table_missing?(message) when is_binary(message) do
    # We intentionally string-match here because tenant table-missing bubbles up
    # through Ash as an Unknown error wrapper.
    String.contains?(message, "package_installations") and
      (String.contains?(message, "undefined_table") or String.contains?(message, "42P01") or
         String.contains?(message, "does not exist"))
  end

  defp tenant_installations_table_missing?(_), do: false

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

  defp load_installation_status_by_slug(tenant) when is_binary(tenant) do
    safe_read(
      fn ->
        Installation
        |> Ash.Query.for_read(:read)
        |> Ash.read!(tenant: tenant)
        |> Enum.reduce(%{}, fn i, acc ->
          slug = i.package_slug

          if is_binary(slug) and String.trim(slug) != "" do
            Map.put(acc, slug, %{
              id: i.id,
              status: i.status,
              enabled: i.enabled,
              installed_at: i.installed_at,
              updated_at: i.updated_at,
              last_error: i.last_error,
              last_error_at: i.last_error_at
            })
          else
            acc
          end
        end)
      end,
      default: %{}
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
      version: Map.get(pkg, :version),
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
