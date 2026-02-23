defmodule FleetPromptWeb.Plugs.AdminTenant do
  @moduledoc """
  Sets the Ash tenant used by AshAdmin from query params, persisting it via a cookie (and session).

  Motivation:
  - AshAdmin is implemented as LiveView(s).
  - LiveView receives `Session:` values from the HTTP request that rendered it.
  - AshAdmin also copies specific cookies into the LiveView session (including `"tenant"`),
    which makes a tenant cookie the most compatible persistence mechanism.

  Behavior:
  - If a signed-in user can be determined for this request, the tenant is pinned to that user's organization.
    Any `tenant` query param is ignored and the cookie/session are updated to the user's org tenant.
  - Otherwise, if `?tenant=` is present, it wins and will update the tenant cookie (and session).
  - If `?tenant=public|none|""`, it clears the tenant cookie (and session).
  - If `?tenant=<slug>` is given (e.g. `demo`), it will normalize to `org_<slug>`.
  - If no `tenant` param is present, it keeps whatever is already stored (cookie wins over session).
  - When a tenant param is provided on a GET/HEAD request, it redirects to the same path
    without the `tenant` query param (to keep URLs clean).
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias FleetPrompt.Accounts.{Organization, User}

  @tenant_cookie "tenant"
  @tenant_session_key "tenant"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn =
      conn
      |> fetch_query_params()
      |> fetch_cookies()

    allowed_tenant = allowed_tenant_for_conn(conn)

    case Map.fetch(conn.params, "tenant") do
      {:ok, raw} ->
        requested = normalize_tenant(raw)

        tenant =
          if is_binary(allowed_tenant) and allowed_tenant != "" do
            allowed_tenant
          else
            requested
          end

        conn =
          conn
          |> apply_tenant(tenant)

        # Keep URLs clean by stripping only the `tenant` query param.
        if conn.method in ["GET", "HEAD"] do
          redirect_without_tenant_param(conn)
        else
          conn
        end

      :error ->
        if is_binary(allowed_tenant) and allowed_tenant != "" do
          conn
          |> apply_tenant(allowed_tenant)
        else
          # No explicit override on this request; keep whatever is already in cookie/session.
          current =
            conn.req_cookies[@tenant_cookie] ||
              get_session(conn, @tenant_session_key)

          conn
          |> Ash.PlugHelpers.set_tenant(current)
          |> assign(:ash_tenant, current)
        end
    end
  end

  defp allowed_tenant_for_conn(conn) do
    cond do
      match?(%Organization{}, conn.assigns[:current_organization]) ->
        org_to_tenant(conn.assigns.current_organization)

      match?(%User{}, conn.assigns[:current_user]) ->
        user = conn.assigns.current_user

        case Map.get(user, :organization) do
          %Organization{} = org -> org_to_tenant(org)
          _ -> tenant_from_session(conn)
        end

      true ->
        tenant_from_session(conn)
    end
  end

  defp tenant_from_session(conn) do
    user_id = get_session(conn, :user_id) || get_session(conn, "user_id")

    if is_binary(user_id) and String.trim(user_id) != "" do
      case safe_load_user_org(user_id) do
        {:ok, %Organization{} = org} -> org_to_tenant(org)
        _ -> nil
      end
    else
      nil
    end
  end

  defp safe_load_user_org(user_id) when is_binary(user_id) do
    try do
      case Ash.get(User, user_id, load: [:organization]) do
        {:ok, %User{} = user} -> {:ok, Map.get(user, :organization)}
        other -> {:error, other}
      end
    rescue
      err -> {:error, err}
    catch
      kind, reason -> {:error, {kind, reason}}
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

  defp apply_tenant(conn, nil) do
    conn
    |> delete_resp_cookie(@tenant_cookie, path: "/")
    |> delete_session(@tenant_session_key)
    |> Ash.PlugHelpers.set_tenant(nil)
    |> assign(:ash_tenant, nil)
  end

  defp apply_tenant(conn, tenant) when is_binary(tenant) do
    conn
    |> put_resp_cookie(@tenant_cookie, tenant,
      # Must be readable by JS so AshAdmin's LiveSocket connect params include `tenant`.
      http_only: false,
      same_site: "Lax",
      path: "/"
    )
    |> put_session(@tenant_session_key, tenant)
    |> Ash.PlugHelpers.set_tenant(tenant)
    |> assign(:ash_tenant, tenant)
  end

  defp redirect_without_tenant_param(conn) do
    remaining =
      conn.query_params
      |> Map.drop(["tenant"])

    location =
      case remaining do
        map when map_size(map) == 0 ->
          conn.request_path

        map ->
          conn.request_path <> "?" <> Plug.Conn.Query.encode(map)
      end

    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
    |> halt()
  end

  defp normalize_tenant(nil), do: nil

  defp normalize_tenant(raw) when is_binary(raw) do
    raw = String.trim(raw)

    cond do
      raw in ["", "public", "none"] ->
        nil

      String.starts_with?(raw, "org_") ->
        if valid_tenant_schema?(raw), do: raw, else: invalid_tenant(raw)

      valid_slug?(raw) ->
        "org_" <> raw

      true ->
        invalid_tenant(raw)
    end
  end

  defp invalid_tenant(raw) do
    Logger.debug("[AdminTenant] Ignoring invalid tenant param", tenant: raw)
    nil
  end

  defp valid_slug?(slug) when is_binary(slug) do
    # Conservative slug rules: lowercase alphanumerics + underscores, 1..63 chars.
    String.length(slug) in 1..63 and String.match?(slug, ~r/^[a-z0-9]+(?:_[a-z0-9]+)*$/)
  end

  defp valid_tenant_schema?(tenant) when is_binary(tenant) do
    # `org_<slug>` where slug follows the same conservative rules.
    case String.split(tenant, "org_", parts: 2) do
      ["", rest] -> valid_slug?(rest)
      _ -> false
    end
  end
end
