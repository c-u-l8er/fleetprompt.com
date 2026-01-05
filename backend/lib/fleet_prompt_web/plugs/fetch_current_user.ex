defmodule FleetPromptWeb.Plugs.FetchCurrentUser do
  @moduledoc """
  Loads the current user from the session and assigns it on the connection.

  In addition to `conn.assigns.current_user`, this plug can also:
  - load and assign the user's `organization` as `conn.assigns.current_organization`
  - default the Ash tenant (schema) to the user's org tenant (`org_<slug>`) when no tenant
    is already present in cookie/session

  This is intended to make multi-tenancy safe by ensuring tenant-scoped reads
  (e.g. Agents) happen within an explicit tenant context.

  Requirements:
  - `fetch_session` must have already run.

  Default behavior:
  - Reads `:user_id` from the session.
  - If present, loads `FleetPrompt.Accounts.User` from the public schema via Ash (with organization loaded).
  - Assigns:
    - `conn.assigns.current_user`
    - `conn.assigns.current_organization`
  - If the user cannot be loaded (deleted/invalid), clears the session key and assigns `nil`.

  Options:
  - `:session_key` (default: `:user_id`) - session key containing the user id
  - `:assign_key` (default: `:current_user`) - assigns loaded user under this key
  - `:org_assign_key` (default: `:current_organization`) - assigns loaded org under this key
  - `:tenant_cookie` (default: `"tenant"`) - cookie name used to persist tenant (compatible with AshAdmin)
  - `:tenant_session_key` (default: `"tenant"`) - session key used to persist tenant
  - `:set_tenant_from_user_org?` (default: `true`) - whether to set tenant from user org when none is present
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias FleetPrompt.Accounts.{Organization, User}

  @impl Plug
  def init(opts) do
    opts
    |> Keyword.put_new(:session_key, :user_id)
    |> Keyword.put_new(:assign_key, :current_user)
    |> Keyword.put_new(:org_assign_key, :current_organization)
    |> Keyword.put_new(:tenant_cookie, "tenant")
    |> Keyword.put_new(:tenant_session_key, "tenant")
    |> Keyword.put_new(:set_tenant_from_user_org?, false)
  end

  @impl Plug
  def call(conn, opts) do
    session_key = Keyword.fetch!(opts, :session_key)
    assign_key = Keyword.fetch!(opts, :assign_key)
    org_assign_key = Keyword.fetch!(opts, :org_assign_key)

    # Ensure we can read tenant cookie state if we want to default tenant from the user.
    conn = fetch_cookies(conn)

    # If something upstream already assigned it, keep it.
    if Map.has_key?(conn.assigns, assign_key) do
      conn
    else
      user_id = get_session(conn, session_key)

      cond do
        is_binary(user_id) and user_id != "" ->
          load_and_assign_user(conn, user_id, session_key, assign_key, org_assign_key, opts)

        true ->
          conn
          |> assign(assign_key, nil)
          |> assign(org_assign_key, nil)
      end
    end
  end

  defp load_and_assign_user(conn, user_id, session_key, assign_key, org_assign_key, opts) do
    # Users live in the public schema; do not pass tenant context here.
    case safe_get_user_with_org(user_id) do
      {:ok, %User{} = user} ->
        org = Map.get(user, :organization)

        conn =
          conn
          |> assign(assign_key, sanitize_user(user))
          |> assign(org_assign_key, org)

        conn

      {:error, reason} ->
        Logger.debug("[FetchCurrentUser] clearing session (user not found/invalid)",
          user_id: user_id,
          reason: inspect(reason)
        )

        conn
        |> delete_session(session_key)
        |> assign(assign_key, nil)
        |> assign(org_assign_key, nil)
    end
  end

  defp maybe_set_tenant_from_user_org(conn, %Organization{} = org, opts) do
    if Keyword.fetch!(opts, :set_tenant_from_user_org?) and not tenant_present?(conn, opts) do
      tenant = org_to_tenant(org)

      if is_binary(tenant) and tenant != "" do
        tenant_cookie = Keyword.fetch!(opts, :tenant_cookie)
        tenant_session_key = Keyword.fetch!(opts, :tenant_session_key)

        conn
        |> put_resp_cookie(tenant_cookie, tenant,
          # Must be readable by JS so AshAdmin's LiveSocket connect params include `tenant`.
          http_only: false,
          same_site: "Lax",
          path: "/"
        )
        |> put_session(tenant_session_key, tenant)
        |> Ash.PlugHelpers.set_tenant(tenant)
        |> assign(:ash_tenant, tenant)
      else
        conn
      end
    else
      conn
    end
  end

  defp maybe_set_tenant_from_user_org(conn, _org, _opts), do: conn

  defp tenant_present?(conn, opts) do
    tenant_cookie = Keyword.fetch!(opts, :tenant_cookie)
    tenant_session_key = Keyword.fetch!(opts, :tenant_session_key)

    cookie_tenant = conn.req_cookies[tenant_cookie]
    session_tenant = get_session(conn, tenant_session_key)
    assigns_tenant = conn.assigns[:ash_tenant]

    (is_binary(cookie_tenant) and cookie_tenant != "") or
      (is_binary(session_tenant) and session_tenant != "") or
      (is_binary(assigns_tenant) and assigns_tenant != "")
  end

  defp org_to_tenant(%Organization{} = org) do
    slug = Map.get(org, :slug)

    if is_binary(slug) and String.trim(slug) != "" do
      "org_" <> String.trim(slug)
    else
      nil
    end
  end

  defp safe_get_user_with_org(user_id) do
    try do
      # Load org so we can expose it to the UI and optionally derive tenant.
      Ash.get(User, user_id, load: [:organization])
    rescue
      err -> {:error, err}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp sanitize_user(%User{} = user) do
    # Avoid accidental leakage to assigns, logs, serialization, etc.
    %{user | hashed_password: nil}
  end
end
