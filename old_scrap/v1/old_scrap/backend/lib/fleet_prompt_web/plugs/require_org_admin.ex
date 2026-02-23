defmodule FleetPromptWeb.Plugs.RequireOrgAdmin do
  @moduledoc """
  Plug to require an org-scoped admin role for protected "admin" routes.

  Intended usage:
  - Place this plug *after* your auth plug(s) that assign `:current_user`.
  - Ensure the request has a selected org/tenant context (e.g. via session).
  - Use it in the `:admin` pipeline or specific admin controllers.

  Authorization model:
  - Preferred: org membership role (per-organization) must be `:owner` or `:admin`.
  - Backward-compatible fallback (optional): if membership resource isn't available,
    allow `conn.assigns.current_user.role` of `:admin` (or `"admin"`).

  Notes:
  - If the request appears to be an Inertia navigation (`x-inertia: true`), redirects
    are performed using `409` + `x-inertia-location` to force a full visit.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  @default_redirect_to "/"
  @default_unauthenticated_redirect_to "/login"

  # Only these membership roles may access admin routes.
  @allowed_roles [:owner, :admin]

  @impl Plug
  def init(opts) do
    %{
      # Where to send users that are authenticated but not authorized (non-inertia)
      redirect_to: Keyword.get(opts, :redirect_to, @default_redirect_to),

      # Where to send users that are not authenticated
      unauthenticated_redirect_to:
        Keyword.get(opts, :unauthenticated_redirect_to, @default_unauthenticated_redirect_to),

      # Whether to fall back to a global `user.role` check when org membership isn't available
      allow_user_role_fallback?: Keyword.get(opts, :allow_user_role_fallback?, true),

      # Which assign keys to read
      user_assign_key: Keyword.get(opts, :user_assign_key, :current_user),
      org_assign_key: Keyword.get(opts, :org_assign_key, :current_organization),

      # Optional override for the membership resource module
      membership_resource:
        Keyword.get(opts, :membership_resource, FleetPrompt.Accounts.OrganizationMembership),

      # Flash messages
      unauthenticated_flash:
        Keyword.get(opts, :unauthenticated_flash, "You must sign in to continue."),
      unauthorized_flash:
        Keyword.get(
          opts,
          :unauthorized_flash,
          "You do not have access to this organization’s admin."
        )
    }
  end

  @impl Plug
  def call(conn, opts) do
    user = Map.get(conn.assigns, opts.user_assign_key)
    org = Map.get(conn.assigns, opts.org_assign_key)

    cond do
      is_nil(user) ->
        deny_unauthenticated(conn, opts)

      is_nil(org) ->
        deny_unauthorized(conn, opts)

      authorized_for_org?(user, org, opts) ->
        conn

      true ->
        deny_unauthorized(conn, opts)
    end
  end

  # -----------------------
  # Authorization
  # -----------------------

  defp authorized_for_org?(user, org, opts) do
    case membership_role_for(user, org, opts) do
      {:ok, role} when role in @allowed_roles ->
        true

      {:ok, _role} ->
        false

      {:error, :membership_unavailable} ->
        if opts.allow_user_role_fallback? do
          global_admin?(user)
        else
          false
        end

      {:error, _reason} ->
        false
    end
  end

  defp membership_role_for(user, org, opts) do
    membership_resource = opts.membership_resource

    if Code.ensure_loaded?(membership_resource) do
      # We intentionally avoid depending on a specific action name; we use `:read`
      # and filter down to a single membership row.
      #
      # Expected membership fields (recommended):
      # - user_id
      # - organization_id
      # - role
      query =
        membership_resource
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(
          expr(user_id == ^user.id and organization_id == ^org.id and status == :active)
        )
        |> Ash.Query.select([:role])

      case safe_read_one(query) do
        {:ok, nil} -> {:ok, nil}
        {:ok, membership} -> {:ok, normalize_role(Map.get(membership, :role))}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :membership_unavailable}
    end
  end

  defp safe_read_one(query) do
    try do
      Ash.read_one(query)
    rescue
      err -> {:error, err}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp global_admin?(user) when is_map(user) do
    role = Map.get(user, :role) || Map.get(user, "role")

    cond do
      role in [:admin, :owner] -> true
      is_binary(role) and role in ["admin", "owner"] -> true
      true -> false
    end
  end

  defp normalize_role(nil), do: nil
  defp normalize_role(role) when role in @allowed_roles, do: role

  defp normalize_role(role) when is_binary(role) do
    case role do
      "owner" -> :owner
      "admin" -> :admin
      _ -> nil
    end
  end

  defp normalize_role(_), do: nil

  # -----------------------
  # Deny helpers
  # -----------------------

  defp deny_unauthenticated(conn, opts) do
    redirect_to = opts.unauthenticated_redirect_to

    if inertia_request?(conn) do
      conn
      |> put_resp_header("x-inertia-location", redirect_to)
      |> send_resp(409, "")
      |> halt()
    else
      conn
      |> put_flash(:error, opts.unauthenticated_flash)
      |> redirect(to: redirect_to)
      |> halt()
    end
  end

  defp deny_unauthorized(conn, opts) do
    redirect_to = opts.redirect_to

    if inertia_request?(conn) do
      conn
      |> put_resp_header("x-inertia-location", redirect_to)
      |> send_resp(409, "")
      |> halt()
    else
      conn
      |> put_flash(:error, opts.unauthorized_flash)
      |> redirect(to: redirect_to)
      |> halt()
    end
  end

  defp inertia_request?(conn) do
    case get_req_header(conn, "x-inertia") do
      ["true" | _] -> true
      ["True" | _] -> true
      _ -> false
    end
  end
end
