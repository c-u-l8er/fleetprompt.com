defmodule FleetPromptWeb.OrgController do
  @moduledoc """
  Switch the current organization (and therefore tenant schema) for the signed-in user.

  This controller is intended to support multi-org membership:

  - Users can belong to multiple organizations via a membership/join resource
    (expected: `FleetPrompt.Accounts.OrganizationMembership`).
  - The "current org" selection is persisted in the session (and the tenant cookie/session)
    so subsequent requests use the correct tenant context.
  - Selection is constrained to organizations the user is a member of.

  Expected routes (example):
    - POST /org/select  -> OrgController.select/2

  Params accepted:
    - "organization_id" (preferred) OR "org_id"
    - OR "slug"

  Optional:
    - "redirect_to" (defaults to Referer, then "/dashboard")
  """

  use FleetPromptWeb, :controller

  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  alias FleetPrompt.Accounts.Organization

  @tenant_cookie "tenant"
  @tenant_session_key "tenant"
  @current_org_session_key :current_org_id

  # POST /org/select
  def select(conn, params) do
    case conn.assigns[:current_user] do
      nil ->
        deny(
          conn,
          "You must sign in to select an organization.",
          redirect_to(conn, params, "/login")
        )

      user ->
        with {:ok, org} <- fetch_target_org(params),
             :ok <- ensure_membership(user, org),
             {:ok, conn} <- persist_current_org(conn, org) do
          ok(conn, org, redirect_to(conn, params, "/dashboard"))
        else
          {:error, :membership_resource_missing} ->
            # Membership resource isn't implemented yet; fail loudly but safely.
            deny(
              conn,
              "Organization membership is not configured yet.",
              redirect_to(conn, params, "/dashboard")
            )

          {:error, :org_not_found} ->
            deny(conn, "Organization not found.", redirect_to(conn, params, "/dashboard"))

          {:error, :forbidden} ->
            deny(
              conn,
              "You do not have access to that organization.",
              redirect_to(conn, params, "/dashboard")
            )

          {:error, _reason} ->
            deny(conn, "Unable to switch organization.", redirect_to(conn, params, "/dashboard"))
        end
    end
  end

  # -----------------------
  # Org lookup
  # -----------------------

  defp fetch_target_org(%{"organization_id" => org_id}) when is_binary(org_id) and org_id != "" do
    fetch_org_by_id(org_id)
  end

  defp fetch_target_org(%{"org_id" => org_id}) when is_binary(org_id) and org_id != "" do
    fetch_org_by_id(org_id)
  end

  defp fetch_target_org(%{"slug" => slug}) when is_binary(slug) and slug != "" do
    fetch_org_by_slug(slug)
  end

  defp fetch_target_org(_params), do: {:error, :org_not_found}

  defp fetch_org_by_id(org_id) when is_binary(org_id) do
    query =
      Organization
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^org_id))

    case Ash.read_one(query) do
      {:ok, %Organization{} = org} -> {:ok, org}
      {:ok, nil} -> {:error, :org_not_found}
      {:error, _} -> {:error, :org_not_found}
    end
  end

  defp fetch_org_by_slug(slug) when is_binary(slug) do
    slug = String.trim(slug)

    query =
      Organization
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(slug == ^slug))

    case Ash.read_one(query) do
      {:ok, %Organization{} = org} -> {:ok, org}
      {:ok, nil} -> {:error, :org_not_found}
      {:error, _} -> {:error, :org_not_found}
    end
  end

  # -----------------------
  # Membership enforcement
  # -----------------------

  defp ensure_membership(user, org) do
    membership_mod = FleetPrompt.Accounts.OrganizationMembership

    if Code.ensure_loaded?(membership_mod) do
      query =
        membership_mod
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(expr(user_id == ^user.id and organization_id == ^org.id))

      case Ash.read_one(query) do
        {:ok, nil} -> {:error, :forbidden}
        {:ok, _membership} -> :ok
        {:error, _} -> {:error, :forbidden}
      end
    else
      {:error, :membership_resource_missing}
    end
  end

  # -----------------------
  # Persistence + tenant
  # -----------------------

  defp persist_current_org(conn, %Organization{} = org) do
    tenant = org_to_tenant(org)

    if is_binary(tenant) and tenant != "" do
      conn =
        conn
        |> Plug.Conn.put_session(@current_org_session_key, org.id)
        |> Plug.Conn.put_resp_cookie(@tenant_cookie, tenant,
          # Must be readable by JS so AshAdmin's LiveSocket connect params include `tenant`.
          http_only: false,
          same_site: "Lax",
          path: "/"
        )
        |> Plug.Conn.put_session(@tenant_session_key, tenant)
        |> Ash.PlugHelpers.set_tenant(tenant)
        |> Plug.Conn.assign(:ash_tenant, tenant)
        |> Plug.Conn.assign(:current_organization, org)

      {:ok, conn}
    else
      {:error, :invalid_tenant}
    end
  end

  defp org_to_tenant(%Organization{} = org) do
    slug = Map.get(org, :slug)

    if is_binary(slug) and String.trim(slug) != "" do
      "org_" <> String.trim(slug)
    else
      nil
    end
  end

  # -----------------------
  # Responses
  # -----------------------

  defp ok(conn, %Organization{} = org, redirect_to) do
    if wants_json?(conn) do
      json(conn, %{
        ok: true,
        redirect_to: redirect_to,
        organization: %{
          id: org.id,
          name: org.name,
          slug: org.slug,
          tier: org.tier
        },
        tenant_schema: org_to_tenant(org)
      })
    else
      redirect(conn, to: redirect_to)
    end
  end

  defp deny(conn, message, redirect_to) do
    if inertia_request?(conn) do
      conn
      |> put_resp_header("x-inertia-location", redirect_to)
      |> send_resp(409, "")
      |> halt()
    else
      conn
      |> put_flash(:error, message)
      |> redirect(to: redirect_to)
      |> halt()
    end
  end

  defp redirect_to(conn, params, default) do
    explicit =
      case Map.get(params, "redirect_to") do
        v when is_binary(v) and v != "" -> String.trim(v)
        _ -> nil
      end

    referer =
      case Plug.Conn.get_req_header(conn, "referer") do
        [v | _] when is_binary(v) and v != "" -> v
        _ -> nil
      end

    explicit || referer || default
  end

  defp wants_json?(conn) do
    Phoenix.Controller.get_format(conn) == "json" or
      has_json_header?(Plug.Conn.get_req_header(conn, "accept")) or
      has_json_header?(Plug.Conn.get_req_header(conn, "content-type"))
  end

  defp has_json_header?(values) when is_list(values) do
    Enum.any?(values, fn v -> is_binary(v) and String.contains?(v, "application/json") end)
  end

  defp inertia_request?(conn) do
    case Plug.Conn.get_req_header(conn, "x-inertia") do
      ["true" | _] -> true
      ["True" | _] -> true
      _ -> false
    end
  end
end
