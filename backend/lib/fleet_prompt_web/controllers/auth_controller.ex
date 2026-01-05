defmodule FleetPromptWeb.AuthController do
  @moduledoc """
  Session-based authentication controller for the Inertia/Svelte app.

  This controller intentionally stays small and "boring":
  - `create/2` authenticates via the Ash `FleetPrompt.Accounts.User` resource and stores `:user_id` in session.
  - `delete/2` clears the session (logout).

  Response behavior:
  - If the request looks like JSON (`Accept: application/json` or format `json`), returns JSON.
  - Otherwise, uses redirects + flashes (useful for non-Inertia fallbacks).

  Notes:
  - This does not implement registration, email confirmation flows, or password reset yet.
  - Tenant selection is handled separately (you already have cookie/session-based tenant persistence in `AdminTenant`).
  """

  use FleetPromptWeb, :controller

  import Ash.Expr, only: [expr: 1]
  require Ash.Query
  require Logger

  alias FleetPrompt.Accounts.{Organization, OrganizationMembership, User}
  alias FleetPrompt.Repo

  @user_id_session_key :user_id

  # -----------------------
  # Registration safety helpers
  # -----------------------

  defp ensure_membership_table_ready do
    # If migrations haven't been run, registration will fail later and rollback the org create.
    # We preflight here so the user gets a clear error.
    case Repo.query("SELECT to_regclass('public.organization_memberships')") do
      {:ok, %{rows: [[nil]]}} -> {:error, :membership_table_missing}
      {:ok, %{rows: [[_]]}} -> :ok
      {:ok, _} -> :ok
      {:error, _} -> {:error, :membership_table_missing}
    end
  rescue
    _ -> {:error, :membership_table_missing}
  end

  defp tenant_schema_exists?(schema) when is_binary(schema) do
    case Repo.query("SELECT 1 FROM pg_namespace WHERE nspname = $1 LIMIT 1", [schema]) do
      {:ok, %{rows: [[1]]}} -> true
      {:ok, %{rows: []}} -> false
      _ -> false
    end
  rescue
    _ -> false
  end

  defp organization_row_exists_for_slug?(slug) when is_binary(slug) do
    case Repo.query("SELECT 1 FROM organizations WHERE slug = $1 LIMIT 1", [slug]) do
      {:ok, %{rows: [[1]]}} -> true
      {:ok, %{rows: []}} -> false
      _ -> false
    end
  rescue
    _ -> false
  end

  defp cleanup_orphaned_tenant_schema(schema, org_slug) when is_binary(schema) do
    Logger.warning(
      "[AuthController] orphaned tenant schema detected; dropping before registration",
      tenant_schema: schema,
      org_slug: org_slug
    )

    _ = Repo.query("DROP SCHEMA IF EXISTS \"#{schema}\" CASCADE")
    :ok
  rescue
    _ -> :ok
  end

  defp ensure_no_orphaned_tenant_schema(schema, org_row_existed?) when is_binary(schema) do
    if org_row_existed? do
      :ok
    else
      if tenant_schema_exists?(schema) do
        {:error, :orphaned_tenant_schema_conflict}
      else
        :ok
      end
    end
  end

  # Only drop tenant schema on failure if it did not exist before this registration attempt.
  # This prevents accidentally deleting an existing tenant when a registration fails.
  defp maybe_cleanup_tenant_schema(_schema, true), do: :ok
  defp maybe_cleanup_tenant_schema(nil, _existed), do: :ok

  defp maybe_cleanup_tenant_schema(schema, false) when is_binary(schema) do
    # Use CASCADE to remove partially-created objects (e.g. tables) if they were created.
    _ = Repo.query("DROP SCHEMA IF EXISTS \"#{schema}\" CASCADE")
    :ok
  rescue
    _ -> :ok
  end

  # GET /login
  #
  # Renders the Inertia `Login` page.
  def new(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: "/dashboard")
    else
      FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Login", %{
        title: "Sign in",
        error: Phoenix.Controller.get_flash(conn, :error)
      })
    end
  end

  # GET /register
  #
  # Renders the Inertia `Register` page.
  def register_new(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: "/dashboard")
    else
      FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Register", %{
        title: "Create your organization",
        error:
          Phoenix.Controller.get_flash(conn, :error) || Phoenix.Controller.get_flash(conn, :info)
      })
    end
  end

  # POST /register
  #
  # Creates:
  # - an Organization (which triggers tenant schema creation via `manage_tenant`)
  # - a User (public schema)
  # - an OrganizationMembership (role: :owner, status: :active)
  #
  # Then signs the user in (stores :user_id, :current_org_id, and tenant cookie/session).
  #
  # Expected params (JSON or form):
  # - email (required)
  # - password (required)
  # - org_name (required)
  # - org_slug (optional; derived from org_name if missing)
  # - name (optional)
  # - redirect_to (optional)
  def register_create(conn, params) when is_map(params) do
    # Support both:
    # 1) nested payloads (from the Svelte Register page):
    #    %{ "organization" => %{...}, "user" => %{...} }
    # 2) legacy flat params:
    #    %{ "org_name" => ..., "org_slug" => ..., "email" => ..., "password" => ... }
    org_params =
      case Map.get(params, "organization") do
        %{} = org -> org
        _ -> %{}
      end

    user_params =
      case Map.get(params, "user") do
        %{} = user -> user
        _ -> %{}
      end

    email =
      user_params
      |> Map.get("email", Map.get(params, "email", ""))
      |> to_string()
      |> String.trim()
      |> String.downcase()

    password =
      user_params
      |> Map.get("password", Map.get(params, "password", ""))
      |> to_string()

    org_name =
      org_params
      |> Map.get("name", Map.get(params, "org_name", ""))
      |> to_string()
      |> String.trim()

    org_slug =
      org_params
      |> Map.get("slug", Map.get(params, "org_slug", org_name))
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 63)

    name =
      user_params
      |> Map.get("name", Map.get(params, "name", ""))
      |> to_string()
      |> String.trim()
      |> case do
        "" -> nil
        v -> v
      end

    cond do
      email == "" or password == "" or org_name == "" or org_slug == "" ->
        if wants_json?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            ok: false,
            error: "missing_fields",
            message: "email, password, and org_name are required"
          })
        else
          conn
          |> put_flash(:error, "Email, password, and organization name are required.")
          |> redirect(to: "/register")
        end

      true ->
        tenant_schema = "org_" <> org_slug
        org_row_existed? = organization_row_exists_for_slug?(org_slug)
        tenant_schema_existed? = tenant_schema_exists?(tenant_schema)

        # If the tenant schema already exists but there is no matching Organization row,
        # we treat this as an orphaned schema from a prior failed registration and
        # proactively drop it so tenant migrations don't collide (e.g. schema_migrations_pkey).
        if tenant_schema_existed? and not org_row_existed? do
          _ = cleanup_orphaned_tenant_schema(tenant_schema, org_slug)
        end

        tenant_schema_existed? = tenant_schema_exists?(tenant_schema)

        with :ok <- ensure_membership_table_ready(),
             :ok <- ensure_no_orphaned_tenant_schema(tenant_schema, org_row_existed?),
             {:ok, %Organization{} = org} <-
               Organization
               |> Ash.Changeset.for_create(:create, %{name: org_name, slug: org_slug, tier: :free})
               |> Ash.create()
               |> (case do
                     {:ok, %Organization{} = org} -> {:ok, org}
                     {:error, err} -> {:error, {:create_org, err}}
                   end),
             {:ok, %User{} = user} <-
               User
               |> Ash.Changeset.for_create(:create, %{
                 email: email,
                 name: name,
                 password: password,
                 organization_id: org.id,
                 role: :user
               })
               |> Ash.create()
               |> (case do
                     {:ok, %User{} = user} -> {:ok, user}
                     {:error, err} -> {:error, {:create_user, err}}
                   end),
             {:ok, _membership} <-
               OrganizationMembership
               |> Ash.Changeset.for_create(:create, %{
                 user_id: user.id,
                 organization_id: org.id,
                 role: :owner,
                 status: :active
               })
               |> Ash.create()
               |> (case do
                     {:ok, membership} -> {:ok, membership}
                     {:error, err} -> {:error, {:create_membership, err}}
                   end) do
          tenant = "org_" <> to_string(org.slug)

          conn =
            conn
            |> configure_session(renew: true)
            |> put_session(@user_id_session_key, user.id)
            |> put_session(:current_org_id, org.id)
            |> Plug.Conn.put_session("tenant", tenant)
            |> Plug.Conn.put_resp_cookie("tenant", tenant,
              http_only: false,
              same_site: "Lax",
              path: "/"
            )
            |> Ash.PlugHelpers.set_tenant(tenant)
            |> assign(:ash_tenant, tenant)
            |> assign(:current_user, sanitize_user(user))
            |> assign(:current_organization, org)

          respond_login_success(conn, sanitize_user(user), params)
        else
          {:error, {step, reason}} ->
            msg =
              if Exception.exception?(reason) do
                Exception.message(reason)
              else
                inspect(reason)
              end

            invalid_messages =
              case reason do
                %Ash.Error.Invalid{errors: errors} when is_list(errors) ->
                  Enum.map(errors, fn e ->
                    if Exception.exception?(e), do: Exception.message(e), else: inspect(e)
                  end)

                _ ->
                  []
              end

            Logger.error(
              "[AuthController] registration failed step=#{inspect(step)} reason=#{inspect(reason)} msg=#{msg} invalid_errors=#{inspect(invalid_messages)}"
            )

            # If this attempt created a brand-new tenant schema but failed later (often during tenant migrations),
            # clean it up so the user can retry without getting stuck on a half-created tenant.
            _ = maybe_cleanup_tenant_schema(tenant_schema, tenant_schema_existed?)

            handle_registration_error(conn, reason, msg, invalid_messages)

          {:error, reason} ->
            msg =
              if Exception.exception?(reason) do
                Exception.message(reason)
              else
                inspect(reason)
              end

            invalid_messages =
              case reason do
                %Ash.Error.Invalid{errors: errors} when is_list(errors) ->
                  Enum.map(errors, fn e ->
                    if Exception.exception?(e), do: Exception.message(e), else: inspect(e)
                  end)

                _ ->
                  []
              end

            Logger.error(
              "[AuthController] registration failed step=:preflight reason=#{inspect(reason)} msg=#{msg} invalid_errors=#{inspect(invalid_messages)}"
            )

            # If this attempt created a brand-new tenant schema but failed later (often during tenant migrations),
            # clean it up so the user can retry without getting stuck on a half-created tenant.
            _ = maybe_cleanup_tenant_schema(tenant_schema, tenant_schema_existed?)

            handle_registration_error(conn, reason, msg, invalid_messages)
        end
    end
  end

  def register_create(conn, _params) do
    if wants_json?(conn) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{ok: false, error: "invalid_params"})
    else
      conn
      |> put_flash(:error, "Invalid registration request.")
      |> redirect(to: "/register")
    end
  end

  defp handle_registration_error(conn, reason, msg, invalid_messages) do
    cond do
      reason == :membership_table_missing ->
        if wants_json?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            ok: false,
            error: "missing_migration",
            message:
              "Registration failed because the memberships table is missing. Run migrations (mix ecto.migrate) and try again."
          })
        else
          conn
          |> put_flash(
            :error,
            "Registration failed because the memberships table is missing. Run migrations (mix ecto.migrate) and try again."
          )
          |> redirect(to: "/register")
        end

      reason == :orphaned_tenant_schema_conflict ->
        if wants_json?(conn) do
          conn
          |> put_status(:conflict)
          |> json(%{
            ok: false,
            error: "tenant_schema_conflict",
            message:
              "A tenant schema already exists for this slug but no matching organization record exists. Try a different slug, or remove the orphaned schema and retry."
          })
        else
          conn
          |> put_flash(
            :error,
            "A tenant schema already exists for this slug but no matching organization record exists. Try a different slug, or remove the orphaned schema and retry."
          )
          |> redirect(to: "/register")
        end

      String.contains?(msg, "organizations_unique_slug_index") or
        String.contains?(msg, "organizations_unique_slug") or
          String.contains?(msg, "unique_slug") ->
        if wants_json?(conn) do
          conn
          |> put_status(:conflict)
          |> json(%{
            ok: false,
            error: "org_slug_taken",
            message: "That organization slug is already taken."
          })
        else
          conn
          |> put_flash(:error, "That organization slug is already taken.")
          |> redirect(to: "/register")
        end

      String.contains?(msg, "users_unique_email_index") or
        String.contains?(msg, "users_unique_email") or
          String.contains?(msg, "unique_email") ->
        if wants_json?(conn) do
          conn
          |> put_status(:conflict)
          |> json(%{
            ok: false,
            error: "email_taken",
            message: "That email is already registered."
          })
        else
          conn
          |> put_flash(:error, "That email is already registered.")
          |> redirect(to: "/register")
        end

      String.contains?(msg, "organization_memberships") and
          (String.contains?(msg, "does not exist") or
             String.contains?(msg, "undefined_table")) ->
        if wants_json?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            ok: false,
            error: "missing_migration",
            message:
              "Registration failed because the memberships table is missing. Run migrations (mix ecto.migrate) and try again.",
            debug: msg,
            errors: invalid_messages
          })
        else
          conn
          |> put_flash(
            :error,
            "Registration failed because the memberships table is missing. Run migrations (mix ecto.migrate) and try again."
          )
          |> redirect(to: "/register")
        end

      String.contains?(msg, "gen_random_uuid") or
        String.contains?(msg, "CREATE SCHEMA") or
          String.contains?(msg, "TenantMigrations") ->
        if wants_json?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            ok: false,
            error: "tenant_setup_failed",
            message:
              "Organization was created, but tenant setup failed. Please contact support or try again later.",
            debug: msg,
            errors: invalid_messages
          })
        else
          conn
          |> put_flash(
            :error,
            "Organization was created, but tenant setup failed. Please contact support or try again later."
          )
          |> redirect(to: "/register")
        end

      invalid_messages != [] ->
        if wants_json?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            ok: false,
            error: "invalid",
            message: "Validation failed.",
            errors: invalid_messages
          })
        else
          conn
          |> put_flash(:error, "Validation failed: " <> Enum.join(invalid_messages, "; "))
          |> redirect(to: "/register")
        end

      true ->
        if wants_json?(conn) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            ok: false,
            error: "registration_failed",
            message: "Registration failed."
          })
        else
          conn
          |> put_flash(:error, "Registration failed.")
          |> redirect(to: "/register")
        end
    end
  end

  # POST /login
  #
  # Params:
  # - email (required)
  # - password (required)
  # - redirect_to (optional; otherwise will use stored return-to from session if present)
  def create(conn, %{"email" => email, "password" => password} = params) do
    email =
      email
      |> to_string()
      |> String.trim()
      |> String.downcase()

    password = password |> to_string()

    with {:ok, %User{} = user} <- fetch_user_by_email(email),
         :ok <- verify_password(user, password) do
      user = sanitize_user(user)

      conn =
        conn
        |> configure_session(renew: true)
        |> put_session(@user_id_session_key, user.id)
        |> assign(:current_user, user)

      respond_login_success(conn, user, params)
    else
      _ ->
        respond_login_failure(conn, params)
    end
  end

  def create(conn, params) do
    respond_login_failure(conn, params)
  end

  # DELETE /logout
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> respond_logout()
  end

  # -----------------------
  # Internals
  # -----------------------

  defp fetch_user_by_email(email) when is_binary(email) do
    if email == "" do
      Bcrypt.no_user_verify()
      {:error, :invalid_credentials}
    else
      # Ensure we explicitly select `hashed_password` since it is marked `public?(false)`
      # on the Ash resource.
      query =
        User
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(expr(email == ^email))
        |> Ash.Query.select([:id, :email, :name, :role, :organization_id, :hashed_password])

      case Ash.read_one(query) do
        {:ok, %User{} = user} ->
          {:ok, user}

        {:ok, nil} ->
          # Mitigate user enumeration timing attacks.
          Bcrypt.no_user_verify()
          {:error, :invalid_credentials}

        {:error, _} ->
          # Avoid leaking DB/Ash errors and keep response shape stable.
          Bcrypt.no_user_verify()
          {:error, :invalid_credentials}
      end
    end
  end

  defp verify_password(%User{hashed_password: hashed}, password)
       when is_binary(hashed) and hashed != "" and is_binary(password) do
    if Bcrypt.verify_pass(password, hashed) do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end

  defp verify_password(_user, _password) do
    # Keep timing closer to the "real" path when credentials are invalid.
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp respond_login_success(conn, user, params) do
    {conn, redirect_to} = pop_redirect_to(conn, params, default: "/dashboard")

    if wants_json?(conn) do
      json(conn, %{
        ok: true,
        redirect_to: redirect_to,
        user: serialize_user(user)
      })
    else
      conn
      |> put_flash(:info, "Signed in.")
      |> redirect(to: redirect_to)
    end
  end

  defp respond_login_failure(conn, params) do
    redirect_to = Map.get(params, "redirect_to") || "/login"

    if wants_json?(conn) do
      conn
      |> put_status(:unauthorized)
      |> json(%{ok: false, error: "invalid_credentials"})
    else
      conn
      |> put_flash(:error, "Invalid email or password.")
      |> redirect(to: redirect_to)
    end
  end

  defp respond_logout(conn) do
    if wants_json?(conn) do
      json(conn, %{ok: true})
    else
      redirect(conn, to: "/")
    end
  end

  defp sanitize_user(%User{} = user) do
    # Avoid accidental leakage to assigns, serialization, logs, etc.
    %{user | hashed_password: nil}
  end

  defp pop_redirect_to(conn, params, opts) when is_map(params) and is_list(opts) do
    explicit = Map.get(params, "redirect_to") |> normalize_blank()
    return_to_key = "user_return_to"
    stored = get_session(conn, return_to_key) |> normalize_blank()

    redirect_to = explicit || stored || Keyword.fetch!(opts, :default)

    conn =
      if stored do
        delete_session(conn, return_to_key)
      else
        conn
      end

    {conn, redirect_to}
  end

  defp normalize_blank(nil), do: nil

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_blank(value) do
    value |> to_string() |> normalize_blank()
  end

  defp wants_json?(conn) do
    Phoenix.Controller.get_format(conn) == "json" or
      has_json_header?(Plug.Conn.get_req_header(conn, "accept")) or
      has_json_header?(Plug.Conn.get_req_header(conn, "content-type"))
  end

  defp has_json_header?(values) when is_list(values) do
    Enum.any?(values, fn v ->
      is_binary(v) and String.contains?(v, "application/json")
    end)
  end

  defp serialize_user(%User{} = user) do
    %{
      id: user.id,
      email: user.email |> to_string(),
      name: user.name,
      role: user.role |> to_string(),
      organization_id: user.organization_id
    }
  end
end
