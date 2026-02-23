defmodule FleetPrompt.Accounts.Auth do
  @moduledoc """
  Authentication helpers for email/password login.

  This module is intentionally framework-agnostic:
  - no Plug/Phoenix session management
  - no controllers
  - just the core "email + password -> user" verification against `FleetPrompt.Accounts.User`

  Expected usage (in your web layer):
  - call `authenticate_by_email_password/3`
  - on success, store `user.id` in the session
  - on failure, return a generic "invalid email or password" message

  Security notes:
  - When a user is not found (or has no password), we call `Bcrypt.no_user_verify/0`
    to reduce user enumeration timing attacks.
  - We return the user with `hashed_password` cleared to reduce accidental leakage.
  """

  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  alias FleetPrompt.Accounts.User

  @type auth_error ::
          :missing_email
          | :missing_password
          | :invalid_credentials
          | {:unexpected, term()}

  @doc """
  Authenticate a user by email/password.

  Returns:
  - `{:ok, user}` when credentials are valid
  - `{:error, :invalid_credentials}` when invalid (do not distinguish not-found vs wrong password)
  - `{:error, :missing_email | :missing_password}` when inputs are blank
  - `{:error, {:unexpected, reason}}` for non-auth errors (e.g. DB/Ash errors)
  """
  @spec authenticate_by_email_password(binary() | nil, binary() | nil, keyword()) ::
          {:ok, User.t()} | {:error, auth_error()}
  def authenticate_by_email_password(email, password, opts \\ []) do
    email = normalize_email(email)
    password = normalize_password(password)

    cond do
      is_nil(email) ->
        {:error, :missing_email}

      is_nil(password) ->
        {:error, :missing_password}

      true ->
        case get_user_for_auth_by_email(email, opts) do
          {:ok, nil} ->
            # Mitigate timing attacks when the email doesn't exist
            Bcrypt.no_user_verify()
            {:error, :invalid_credentials}

          {:ok, %User{} = user} ->
            verify_user_password(user, password)

          {:error, reason} ->
            {:error, {:unexpected, reason}}
        end
    end
  end

  @doc """
  Fetch a user by id.

  This is useful for a `fetch_current_user` plug in the web layer.
  """
  @spec get_user(binary(), keyword()) :: {:ok, User.t() | nil} | {:error, term()}
  def get_user(user_id, opts \\ []) when is_binary(user_id) do
    query =
      User
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^user_id))
      |> Ash.Query.select([:id, :email, :name, :role, :organization_id, :confirmed_at])

    Ash.read_one(query, opts)
  end

  @doc """
  Hash a plaintext password using bcrypt.

  You generally won't call this directly because `User.create` already hashes
  via its change, but it's handy for tests or one-off operations.
  """
  @spec hash_password(binary()) :: binary()
  def hash_password(password) when is_binary(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  # -------------------
  # Internal helpers
  # -------------------

  defp get_user_for_auth_by_email(email, opts) when is_binary(email) do
    # Ensure we select the hashed password explicitly since it's marked `public?(false)`.
    # (Even though Ash typically returns it internally, being explicit avoids surprises.)
    query =
      User
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(email == ^email))
      |> Ash.Query.select([
        :id,
        :email,
        :hashed_password,
        :name,
        :role,
        :organization_id,
        :confirmed_at
      ])

    Ash.read_one(query, opts)
  end

  defp verify_user_password(%User{} = user, password) when is_binary(password) do
    hashed = Map.get(user, :hashed_password)

    cond do
      not is_binary(hashed) or hashed == "" ->
        # Mitigate timing attacks when the account has no password set
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      Bcrypt.verify_pass(password, hashed) ->
        {:ok, clear_hashed_password(user)}

      true ->
        {:error, :invalid_credentials}
    end
  end

  defp clear_hashed_password(%User{} = user) do
    # Avoid accidental leakage (logs, serialization, etc.)
    %{user | hashed_password: nil}
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email = email |> String.trim()

    if email == "" do
      nil
    else
      # We store email as :ci_string so case doesn't matter; normalizing helps consistency.
      String.downcase(email)
    end
  end

  defp normalize_password(nil), do: nil

  defp normalize_password(password) when is_binary(password) do
    password = String.trim(password)
    if password == "", do: nil, else: password
  end
end
