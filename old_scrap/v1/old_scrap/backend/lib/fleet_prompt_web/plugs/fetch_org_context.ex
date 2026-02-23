defmodule FleetPromptWeb.Plugs.FetchOrgContext do
  @moduledoc """
  Selects the current Organization for the signed-in user (based on memberships),
  and sets the Ash tenant context (`org_<slug>`).

  This plug is designed for schema-per-tenant multi-tenancy where:

  - Organizations + Users + Memberships live in the **public** schema.
  - Tenant-scoped resources (Agents, etc.) live in `org_<slug>` schemas.

  What it does:
  1. Loads the user's organization memberships (if the membership resource exists).
  2. Computes the "allowed orgs" set (orgs the user is a member of).
  3. Chooses the "current org" using precedence:
     - query param `org_id` (uuid) or `org` (slug), if allowed
     - session `:current_org_id`, if allowed
     - `user.organization_id`, if allowed (legacy single-org default)
     - first allowed org
  4. Persists selection to session (`:current_org_id`) and sets:
     - `conn.assigns.current_organization`
     - `conn.assigns.current_membership` (if available)
     - `conn.assigns.current_role` (if available)
     - `conn.assigns.ash_tenant` + `Ash.PlugHelpers.set_tenant/2`
     - `tenant` cookie + session key (for AshAdmin compatibility)

  Notes:
  - This plug is intentionally defensive: if membership resources are not yet implemented,
    it will fall back to `user.organization_id` (if present) and will not crash.
  - Place this plug *after* you load `current_user` (e.g. `FetchCurrentUser`) and
    *before* tenant-sensitive work.
  """

  @behaviour Plug

  import Plug.Conn
  import Ash.Expr, only: [expr: 1]
  require Ash.Query
  require Logger

  alias FleetPrompt.Accounts.{Organization, User}

  @default_session_org_id_key :current_org_id
  @default_tenant_cookie "tenant"
  @default_tenant_session_key "tenant"

  @impl Plug
  def init(opts) do
    opts
    |> Keyword.put_new(:session_org_id_key, @default_session_org_id_key)
    |> Keyword.put_new(:tenant_cookie, @default_tenant_cookie)
    |> Keyword.put_new(:tenant_session_key, @default_tenant_session_key)
    |> Keyword.put_new(:param_org_id_key, "org_id")
    |> Keyword.put_new(:param_org_slug_key, "org")
    |> Keyword.put_new(:assign_org_key, :current_organization)
    |> Keyword.put_new(:assign_membership_key, :current_membership)
    |> Keyword.put_new(:assign_role_key, :current_role)
    |> Keyword.put_new(:set_tenant_cookie?, true)
    |> Keyword.put_new(:set_tenant_session?, true)
    |> Keyword.put_new(:clear_invalid_selection?, true)
  end

  @impl Plug
  def call(conn, opts) do
    conn = fetch_query_params(conn)
    conn = fetch_cookies(conn)

    case Map.get(conn.assigns, :current_user) do
      %User{} = user ->
        apply_for_user(conn, user, opts)

      _ ->
        # No authenticated user: do not invent org context.
        conn
    end
  end

  # -----------------------
  # Core selection
  # -----------------------

  defp apply_for_user(conn, %User{} = user, opts) do
    allowed =
      case load_allowed_orgs(user) do
        {:ok, allowed} ->
          allowed

        {:error, reason} ->
          Logger.debug("[FetchOrgContext] failed to load org memberships",
            user_id: user.id,
            reason: inspect(reason)
          )

          %{}
      end

    available_org_entries =
      allowed
      |> Map.values()
      |> Enum.filter(fn
        %{org: org} when not is_nil(org) -> true
        _ -> false
      end)

    available_organizations =
      available_org_entries
      |> Enum.map(& &1.org)

    conn =
      conn
      |> assign(:available_org_memberships, available_org_entries)
      |> assign(:available_organizations, available_organizations)

    {selected_org, selected_membership} =
      select_org(conn, user, allowed, opts)

    if is_nil(selected_org) do
      maybe_clear_invalid_selection(conn, opts)
    else
      tenant = org_to_tenant(selected_org)

      conn
      |> assign(Keyword.fetch!(opts, :assign_org_key), selected_org)
      |> assign(Keyword.fetch!(opts, :assign_membership_key), selected_membership)
      |> assign(Keyword.fetch!(opts, :assign_role_key), membership_role(selected_membership))
      |> persist_current_org_id(selected_org.id, opts)
      |> persist_tenant(tenant, opts)
      |> Ash.PlugHelpers.set_tenant(tenant)
      |> assign(:ash_tenant, tenant)
    end
  end

  defp maybe_clear_invalid_selection(conn, opts) do
    if Keyword.fetch!(opts, :clear_invalid_selection?) do
      conn
      |> delete_session(Keyword.fetch!(opts, :session_org_id_key))
    else
      conn
    end
  end

  # allowed :: %{org_id => %{org: org, membership: membership}}
  defp select_org(conn, %User{} = user, allowed, opts) when is_map(allowed) do
    # 1) query params
    param_org_id_key = Keyword.fetch!(opts, :param_org_id_key)
    param_org_slug_key = Keyword.fetch!(opts, :param_org_slug_key)

    requested_org =
      case {Map.get(conn.params, param_org_id_key), Map.get(conn.params, param_org_slug_key)} do
        {org_id, _} when is_binary(org_id) and org_id != "" ->
          Map.get(allowed, org_id)

        {_, slug} when is_binary(slug) and slug != "" ->
          find_allowed_by_slug(allowed, slug)

        _ ->
          nil
      end

    if requested_org do
      {requested_org.org, requested_org.membership}
    else
      # 2) session
      session_org_id_key = Keyword.fetch!(opts, :session_org_id_key)
      session_org_id = get_session(conn, session_org_id_key)

      session_pick =
        if is_binary(session_org_id) and session_org_id != "" do
          Map.get(allowed, session_org_id)
        else
          nil
        end

      if session_pick do
        {session_pick.org, session_pick.membership}
      else
        # 3) legacy user.organization_id (if still present) as default
        legacy_org_id = Map.get(user, :organization_id)

        legacy_pick =
          if is_binary(legacy_org_id) and legacy_org_id != "" do
            Map.get(allowed, legacy_org_id)
          else
            nil
          end

        if legacy_pick do
          {legacy_pick.org, legacy_pick.membership}
        else
          # 4) first allowed org (stable-ish by name then id)
          allowed
          |> Map.values()
          |> Enum.sort_by(fn %{org: org} ->
            {to_string(Map.get(org, :name) || ""), to_string(org.id)}
          end)
          |> case do
            [%{org: org, membership: membership} | _] -> {org, membership}
            _ -> {nil, nil}
          end
        end
      end
    end
  end

  defp find_allowed_by_slug(allowed, slug) when is_map(allowed) and is_binary(slug) do
    slug = slug |> String.trim()

    Enum.find_value(Map.values(allowed), fn
      %{org: org} = entry ->
        if to_string(Map.get(org, :slug) || "") == slug, do: entry, else: nil

      _ ->
        nil
    end)
  end

  # -----------------------
  # Persistence
  # -----------------------

  defp persist_current_org_id(conn, org_id, opts) when is_binary(org_id) do
    put_session(conn, Keyword.fetch!(opts, :session_org_id_key), org_id)
  end

  defp persist_tenant(conn, nil, _opts), do: conn

  defp persist_tenant(conn, tenant, opts) when is_binary(tenant) do
    conn
    |> maybe_put_tenant_cookie(tenant, opts)
    |> maybe_put_tenant_session(tenant, opts)
  end

  defp maybe_put_tenant_cookie(conn, tenant, opts) do
    if Keyword.fetch!(opts, :set_tenant_cookie?) do
      cookie = Keyword.fetch!(opts, :tenant_cookie)

      put_resp_cookie(conn, cookie, tenant,
        # Must be readable by JS so AshAdmin's LiveSocket connect params include `tenant`.
        http_only: false,
        same_site: "Lax",
        path: "/"
      )
    else
      conn
    end
  end

  defp maybe_put_tenant_session(conn, tenant, opts) do
    if Keyword.fetch!(opts, :set_tenant_session?) do
      put_session(conn, Keyword.fetch!(opts, :tenant_session_key), tenant)
    else
      conn
    end
  end

  # -----------------------
  # Loading allowed orgs
  # -----------------------

  defp load_allowed_orgs(%User{} = user) do
    membership_mod = FleetPrompt.Accounts.OrganizationMembership

    if Code.ensure_loaded?(membership_mod) do
      # Expectation for the membership resource:
      # - fields: :user_id, :organization_id, :role
      # - relationship: belongs_to :organization, Organization
      # We load the organization to get the slug for tenant derivation.
      memberships_query =
        membership_mod
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(expr(user_id == ^user.id))
        |> Ash.Query.load([:organization])

      case Ash.read(memberships_query) do
        {:ok, memberships} ->
          allowed =
            memberships
            |> Enum.reduce(%{}, fn m, acc ->
              org = Map.get(m, :organization)

              org_id =
                Map.get(m, :organization_id) ||
                  Map.get(org || %{}, :id)

              if is_binary(org_id) and org do
                Map.put(acc, org_id, %{org: org, membership: m})
              else
                acc
              end
            end)

          # Transition aid: if memberships exist but the user has none yet (or the load returned
          # no rows), fall back to the legacy `user.organization_id` if present.
          allowed =
            if map_size(allowed) == 0 do
              legacy_org_id = Map.get(user, :organization_id)

              if is_binary(legacy_org_id) and legacy_org_id != "" do
                legacy_query =
                  Organization
                  |> Ash.Query.for_read(:read)
                  |> Ash.Query.filter(expr(id == ^legacy_org_id))

                case Ash.read_one(legacy_query) do
                  {:ok, %Organization{} = org} ->
                    Map.put(allowed, org.id, %{org: org, membership: nil})

                  _ ->
                    allowed
                end
              else
                allowed
              end
            else
              allowed
            end

          {:ok, allowed}

        {:error, err} ->
          {:error, err}
      end
    else
      # Fallback: if memberships aren't implemented yet, allow only the legacy org_id.
      legacy_org_id = Map.get(user, :organization_id)

      if is_binary(legacy_org_id) and legacy_org_id != "" do
        query =
          Organization
          |> Ash.Query.for_read(:read)
          |> Ash.Query.filter(expr(id == ^legacy_org_id))

        case Ash.read_one(query) do
          {:ok, %Organization{} = org} ->
            {:ok, %{org.id => %{org: org, membership: nil}}}

          {:ok, nil} ->
            {:ok, %{}}

          {:error, err} ->
            {:error, err}
        end
      else
        {:ok, %{}}
      end
    end
  rescue
    err -> {:error, err}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # -----------------------
  # Helpers
  # -----------------------

  defp org_to_tenant(%Organization{} = org) do
    slug = Map.get(org, :slug)

    if is_binary(slug) and String.trim(slug) != "" do
      "org_" <> String.trim(slug)
    else
      nil
    end
  end

  defp membership_role(nil), do: nil

  defp membership_role(membership) when is_map(membership) do
    Map.get(membership, :role) || Map.get(membership, "role")
  end
end
