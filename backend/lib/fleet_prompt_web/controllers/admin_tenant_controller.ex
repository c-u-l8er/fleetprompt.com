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

  alias FleetPrompt.Accounts.Organization

  require Ash.Query

  @tenant_cookie "tenant"
  @tenant_session_key "tenant"

  def index(conn, params) do
    conn = Plug.Conn.fetch_cookies(conn)

    current_tenant =
      conn.req_cookies[@tenant_cookie] ||
        get_session(conn, @tenant_session_key)

    # Convenience: allow `GET /admin/tenant?tenant=demo` to immediately set the cookie
    # and refresh the page without requiring a form post.
    if Map.has_key?(params, "tenant") do
      tenant = normalize_tenant(params["tenant"])

      conn
      |> persist_tenant_cookie(tenant)
      |> persist_tenant_session(tenant)
      |> redirect(to: ~p"/admin/tenant")
    else
      organizations =
        case Organization |> Ash.Query.for_read(:read) |> Ash.read() do
          {:ok, orgs} -> orgs
          {:error, _} -> []
        end

      render(conn, :index,
        organizations: organizations,
        current_tenant: current_tenant
      )
    end
  end

  def select(conn, %{"tenant" => raw}) do
    tenant = normalize_tenant(raw)

    conn =
      conn
      |> persist_tenant_cookie(tenant)
      |> persist_tenant_session(tenant)

    redirect(conn, to: ~p"/admin")
  end

  def select(conn, _params) do
    conn
    |> put_flash(:error, "Missing tenant selection.")
    |> redirect(to: ~p"/admin/tenant")
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
