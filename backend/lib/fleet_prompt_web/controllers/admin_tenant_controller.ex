defmodule FleetPromptWeb.AdminTenantController do
  @moduledoc """
  Tenant selector UI for AshAdmin.

  AshAdmin is a LiveView and derives its tenant from the request that mounts it.
  AshAdmin also replicates specific cookies (including `"tenant"`) into the LiveView
  session, so the most compatible approach is:

  - store the selected tenant in a cookie named `"tenant"`
  - redirect to `/admin` so the browser sends the cookie on the next request
  """

  use FleetPromptWeb, :controller

  # This page renders its own header chrome (homepage-style header), so we
  # override the admin layout with the minimal Inertia layout to avoid
  # double headers.
  plug(:put_layout, html: {FleetPromptWeb.Layouts, :inertia})

  import Ash.Expr, only: [expr: 1]

  alias FleetPrompt.Accounts.{Organization, OrganizationMembership}

  require Ash.Query

  @tenant_cookie "tenant"
  @tenant_session_key "tenant"

  def index(conn, params) do
    conn = Plug.Conn.fetch_cookies(conn)

    current_tenant =
      conn.req_cookies[@tenant_cookie] ||
        get_session(conn, @tenant_session_key)

    allowed_orgs = allowed_admin_organizations(conn)
    allowed_tenants = Enum.map(allowed_orgs, &org_to_tenant/1)

    # Convenience: allow `GET /admin/tenant?tenant=demo` to immediately set the cookie
    # and refresh the page without requiring a form post.
    if Map.has_key?(params, "tenant") do
      raw = params["tenant"]

      case parse_tenant_param(raw) do
        {:ok, tenant} ->
          if tenant_allowed?(tenant, allowed_tenants) do
            conn
            |> persist_tenant_cookie(tenant)
            |> persist_tenant_session(tenant)
            |> redirect(to: ~p"/admin/tenant")
          else
            conn
            |> put_flash(:error, "You do not have access to that organization tenant.")
            |> redirect(to: ~p"/admin/tenant")
          end

        {:error, :invalid} ->
          conn
          |> put_flash(:error, "Invalid tenant selection.")
          |> redirect(to: ~p"/admin/tenant")
      end
    else
      render(conn, :index,
        organizations: allowed_orgs,
        current_tenant: current_tenant
      )
    end
  end

  def select(conn, %{"tenant" => raw}) do
    allowed_orgs = allowed_admin_organizations(conn)
    allowed_tenants = Enum.map(allowed_orgs, &org_to_tenant/1)

    case parse_tenant_param(raw) do
      {:ok, tenant} ->
        if tenant_allowed?(tenant, allowed_tenants) do
          conn =
            conn
            |> persist_tenant_cookie(tenant)
            |> persist_tenant_session(tenant)

          redirect(conn, to: ~p"/admin")
        else
          conn
          |> put_flash(:error, "You do not have access to that organization tenant.")
          |> redirect(to: ~p"/admin/tenant")
        end

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "Invalid tenant selection.")
        |> redirect(to: ~p"/admin/tenant")
    end
  end

  def select(conn, _params) do
    conn
    |> put_flash(:error, "Missing tenant selection.")
    |> redirect(to: ~p"/admin/tenant")
  end

  # --- authorization / scoping ---
  #
  # Admin tenant selection must be restricted to orgs where the current user has an
  # owner/admin membership. This prevents cross-tenant access via cookie tampering
  # or query parameters.

  defp allowed_admin_organizations(conn) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        []

      not Code.ensure_loaded?(OrganizationMembership) ->
        []

      true ->
        query =
          OrganizationMembership
          |> Ash.Query.for_read(:read)
          |> Ash.Query.filter(
            expr(user_id == ^user.id and status == :active and role in [:owner, :admin])
          )
          |> Ash.Query.load([:organization])

        case Ash.read(query) do
          {:ok, memberships} ->
            memberships
            |> Enum.map(&Map.get(&1, :organization))
            |> Enum.reject(&is_nil/1)

          {:error, _} ->
            []
        end
    end
  end

  defp org_to_tenant(org) do
    slug = to_string(Map.get(org, :slug) || "")
    slug = String.trim(slug)

    if slug == "" do
      nil
    else
      "org_" <> slug
    end
  end

  # Allow clearing to public, but otherwise require the tenant to be one of the allowed org tenants.
  defp tenant_allowed?(nil, _allowed), do: true
  defp tenant_allowed?(tenant, allowed) when is_binary(tenant), do: tenant in allowed

  # Parse and validate raw tenant input while preserving "public/none" semantics.
  # This avoids treating arbitrary garbage as "clear tenant".
  defp parse_tenant_param(raw) do
    raw = if is_binary(raw), do: String.trim(raw), else: ""

    normalized = normalize_tenant(raw)

    cond do
      normalized != nil ->
        {:ok, normalized}

      raw in ["", "public", "none"] ->
        {:ok, nil}

      true ->
        {:error, :invalid}
    end
  end

  # --- persistence ---

  defp persist_tenant_cookie(conn, nil) do
    Plug.Conn.delete_resp_cookie(conn, @tenant_cookie, path: "/")
  end

  defp persist_tenant_cookie(conn, tenant) when is_binary(tenant) do
    # AshAdmin’s JS hooks read/write `document.cookie` for `"tenant"`, so this cookie
    # must NOT be httpOnly.
    Plug.Conn.put_resp_cookie(conn, @tenant_cookie, tenant,
      http_only: false,
      same_site: "Lax",
      path: "/"
    )
  end

  defp persist_tenant_session(conn, nil) do
    Plug.Conn.delete_session(conn, @tenant_session_key)
  end

  defp persist_tenant_session(conn, tenant) when is_binary(tenant) do
    Plug.Conn.put_session(conn, @tenant_session_key, tenant)
  end

  # --- normalization ---

  defp normalize_tenant(nil), do: nil

  defp normalize_tenant(raw) when is_binary(raw) do
    raw = String.trim(raw)

    cond do
      raw in ["", "public", "none"] ->
        nil

      String.starts_with?(raw, "org_") ->
        if valid_tenant_schema?(raw), do: raw, else: nil

      valid_slug?(raw) ->
        "org_" <> raw

      true ->
        nil
    end
  end

  defp valid_slug?(slug) when is_binary(slug) do
    String.length(slug) in 1..63 and String.match?(slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
  end

  defp valid_tenant_schema?(tenant) when is_binary(tenant) do
    case String.split(tenant, "org_", parts: 2) do
      ["", rest] -> valid_slug?(rest)
      _ -> false
    end
  end
end
