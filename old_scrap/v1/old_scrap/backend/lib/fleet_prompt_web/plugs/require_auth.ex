defmodule FleetPromptWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug to require an authenticated user for protected routes.

  Assumptions:
  - Auth state is stored in the session as a user id (default key: `:user_id`).
  - If authenticated, this plug assigns the user struct to `conn.assigns.current_user`
    (configurable via `:assign_key`).
  - If not authenticated, this plug redirects to `/login` (configurable via `:redirect_to`).

  Inertia behavior:
  - For Inertia requests (those with the `x-inertia` request header), redirects should be
    done via `409` + `x-inertia-location` to ensure the client performs a full visit.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias FleetPrompt.Accounts.User

  @default_redirect_to "/login"
  @default_session_key :user_id
  @default_assign_key :current_user
  @default_return_to_key "user_return_to"

  @impl Plug
  def init(opts) do
    %{
      redirect_to: Keyword.get(opts, :redirect_to, @default_redirect_to),
      session_key: Keyword.get(opts, :session_key, @default_session_key),
      assign_key: Keyword.get(opts, :assign_key, @default_assign_key),
      return_to_key: Keyword.get(opts, :return_to_key, @default_return_to_key),
      flash_error: Keyword.get(opts, :flash_error, "You must sign in to continue.")
    }
  end

  @impl Plug
  def call(conn, opts) do
    assign_key = opts.assign_key

    cond do
      Map.has_key?(conn.assigns, assign_key) and not is_nil(conn.assigns[assign_key]) ->
        conn

      true ->
        user_id = get_session(conn, opts.session_key)

        case fetch_user(user_id) do
          {:ok, %User{} = user} ->
            assign(conn, assign_key, user)

          _ ->
            conn
            |> maybe_store_return_to(opts)
            |> deny(opts)
        end
    end
  end

  defp fetch_user(nil), do: {:error, :missing_user_id}
  defp fetch_user(""), do: {:error, :missing_user_id}

  defp fetch_user(user_id) when is_binary(user_id) do
    # Prefer a non-raising call so this plug never crashes the request.
    case Ash.get(User, user_id) do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  rescue
    err -> {:error, err}
  end

  defp maybe_store_return_to(conn, opts) do
    # Only store return_to for safe, idempotent requests.
    if conn.method in ["GET", "HEAD"] do
      path_with_query =
        case conn.query_string do
          "" -> conn.request_path
          qs -> conn.request_path <> "?" <> qs
        end

      put_session(conn, opts.return_to_key, path_with_query)
    else
      conn
    end
  end

  defp deny(conn, opts) do
    redirect_to = opts.redirect_to

    if inertia_request?(conn) do
      conn
      |> put_resp_header("x-inertia-location", redirect_to)
      |> send_resp(409, "")
      |> halt()
    else
      conn
      |> put_flash(:error, opts.flash_error)
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
