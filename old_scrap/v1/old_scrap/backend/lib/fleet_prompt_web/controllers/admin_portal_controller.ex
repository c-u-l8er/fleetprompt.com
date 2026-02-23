defmodule FleetPromptWeb.AdminPortalController do
  @moduledoc """
  Controller-rendered Admin Portal.

  This is intended to be a branded, UX-friendly landing page for admin workflows,
  including:
  - showing the current tenant context (public vs `org_<slug>`)
  - listing organizations and providing quick links into AshAdmin
  - providing a clear entry point to the tenant selector

  AshAdmin itself is LiveView and reads tenant context from cookies/session. For
  maximum compatibility, we treat the `"tenant"` cookie as the source of truth
  when present.
  """

  use FleetPromptWeb, :controller

  alias FleetPrompt.Accounts.Organization

  require Ash.Query

  @tenant_cookie "tenant"
  @tenant_session_key "tenant"

  def index(conn, _params) do
    conn = Plug.Conn.fetch_cookies(conn)

    current_tenant =
      conn.req_cookies[@tenant_cookie] ||
        get_session(conn, @tenant_session_key)

    organizations =
      case Organization |> Ash.Query.for_read(:read) |> Ash.read() do
        {:ok, orgs} -> orgs
        {:error, _} -> []
      end

    render(conn, :index,
      organizations: organizations,
      current_tenant: normalize_current_tenant(current_tenant)
    )
  end

  defp normalize_current_tenant(nil), do: nil

  defp normalize_current_tenant(tenant) when is_binary(tenant) do
    tenant = String.trim(tenant)

    cond do
      tenant in ["", "public", "none", "null"] -> nil
      true -> tenant
    end
  end

  defp normalize_current_tenant(_), do: nil
end
