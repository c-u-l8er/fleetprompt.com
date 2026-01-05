defmodule FleetPromptWeb.InertiaHelpers do
  @moduledoc """
  Helpers for rendering Inertia responses with shared props merged into every page.

  This module is intentionally small and conservative:
  - It performs a *deep merge* of "shared props" into per-page props.
  - Per-page props win when keys collide.
  - It does not assume any particular authentication implementation; it simply
    reads conventional assigns if present (e.g. `:current_user`, `:ash_tenant`,
    `:current_organization`).

  Typical usage in a controller:

      defmodule FleetPromptWeb.SomeController do
        use FleetPromptWeb, :controller
        import FleetPromptWeb.InertiaHelpers, only: [render_inertia: 3]

        def index(conn, _params) do
          render_inertia(conn, "Dashboard", %{title: "Dashboard"})
        end
      end
  """

  @doc """
  Render an Inertia page, automatically merging shared props into the given props.

  Accepts the same first 3 args as `Inertia.Controller.render_inertia/3`.

  If `Inertia.Controller.render_inertia/4` exists (library version-dependent),
  you may also pass `opts` as a fourth argument.
  """
  def render_inertia(conn, component, props) when is_map(props) do
    merged = deep_merge(shared_props(conn), props)
    Inertia.Controller.render_inertia(conn, component, merged)
  end

  def render_inertia(conn, component, props, opts) when is_map(props) and is_list(opts) do
    merged = deep_merge(shared_props(conn), props)

    # Some versions of inertia_phoenix expose `render_inertia/4`, others only `/3`.
    if function_exported?(Inertia.Controller, :render_inertia, 4) do
      Inertia.Controller.render_inertia(conn, component, merged, opts)
    else
      Inertia.Controller.render_inertia(conn, component, merged)
    end
  end

  @doc """
  Returns the shared Inertia props for the current request.

  This is the single place where you decide what should be globally available
  to the frontend (e.g. `auth.user`, current tenant, etc.).
  """
  def shared_props(conn) do
    current_user = Map.get(conn.assigns, :current_user)

    current_org =
      Map.get(conn.assigns, :current_organization) || Map.get(conn.assigns, :current_org)

    serialized_user = serialize_user(current_user)

    tenant_schema = Map.get(conn.assigns, :ash_tenant)
    tenant_slug = tenant_to_slug(tenant_schema)

    available_organizations = Map.get(conn.assigns, :available_organizations) || []
    organizations = Enum.map(available_organizations, &serialize_org/1)

    %{
      # Top-level props for convenience in Svelte (e.g. AppShell header)
      user: serialized_user,
      tenant: tenant_slug,
      tenant_schema: tenant_schema,

      # Org context for the header org switcher
      current_organization: serialize_org(current_org),
      organizations: organizations,

      # Structured namespaces (useful for future expansion)
      auth: %{
        user: serialized_user
      },
      tenant_context: %{
        schema: tenant_schema,
        slug: tenant_slug,
        organization: serialize_org(current_org),
        organizations: organizations
      },
      fp: %{
        request_path: Map.get(conn.assigns, :fp_request_path) || conn.request_path
      }
    }
  end

  @doc """
  Deep-merge two maps.

  - When both values are maps, they are recursively merged.
  - Otherwise, the right-hand value wins.

  This is useful so you can do:

      shared: %{auth: %{user: ...}}
      page:   %{auth: %{return_to: "/chat"}}

  and get:

      %{auth: %{user: ..., return_to: "/chat"}}
  """
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, lval, rval ->
      if is_map(lval) and is_map(rval) do
        deep_merge(lval, rval)
      else
        rval
      end
    end)
  end

  # -----------------------
  # Serialization helpers
  # -----------------------

  defp serialize_user(nil), do: nil

  defp serialize_user(user) when is_map(user) do
    %{
      id: Map.get(user, :id) || Map.get(user, "id"),
      email: Map.get(user, :email) || Map.get(user, "email"),
      name: Map.get(user, :name) || Map.get(user, "name"),
      role: Map.get(user, :role) || Map.get(user, "role")
    }
    |> drop_nils()
  end

  defp serialize_org(nil), do: nil

  defp serialize_org(org) when is_map(org) do
    %{
      id: Map.get(org, :id) || Map.get(org, "id"),
      name: Map.get(org, :name) || Map.get(org, "name"),
      slug: Map.get(org, :slug) || Map.get(org, "slug"),
      tier: Map.get(org, :tier) || Map.get(org, "tier")
    }
    |> drop_nils()
  end

  defp tenant_to_slug(nil), do: nil

  defp tenant_to_slug(tenant) when is_binary(tenant) do
    tenant = String.trim(tenant)

    cond do
      tenant == "" ->
        nil

      String.starts_with?(tenant, "org_") ->
        String.replace_prefix(tenant, "org_", "")

      true ->
        tenant
    end
  end

  defp drop_nils(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_k, nil}, acc -> acc
      {k, v}, acc -> Map.put(acc, k, v)
    end)
  end
end
