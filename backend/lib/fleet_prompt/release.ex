defmodule FleetPrompt.Release do
  @moduledoc """
  Release tasks for running database migrations/rollbacks in production.

  Typical usage (in a release):

      bin/fleet_prompt eval "FleetPrompt.Release.migrate()"

  Or rollback to a specific migration version:

      bin/fleet_prompt eval "FleetPrompt.Release.rollback(20240101000000)"
  """

  @app :fleet_prompt

  @doc """
  Runs all pending Ecto migrations for all configured repos.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      result =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, migrations_path(), :up, all: true)
        end)

      case result do
        {:ok, _result} ->
          :ok

        {:ok, _result, _log} ->
          :ok

        {:error, reason} ->
          raise RuntimeError,
                "migration failed for #{inspect(repo)}: #{inspect(reason)}"

        other ->
          raise RuntimeError,
                "unexpected result from Ecto.Migrator.with_repo for #{inspect(repo)}: #{inspect(other)}"
      end
    end

    :ok
  end

  @doc """
  Rolls back migrations for all configured repos.

  `version` must be the integer migration version (e.g. `20240101000000`).
  """
  def rollback(version) when is_integer(version) do
    load_app()

    for repo <- repos() do
      result =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, migrations_path(), :down, to: version)
        end)

      case result do
        {:ok, _result} ->
          :ok

        {:ok, _result, _log} ->
          :ok

        {:error, reason} ->
          raise RuntimeError,
                "rollback failed for #{inspect(repo)} to #{version}: #{inspect(reason)}"

        other ->
          raise RuntimeError,
                "unexpected result from Ecto.Migrator.with_repo for #{inspect(repo)} to #{version}: #{inspect(other)}"
      end
    end

    :ok
  end

  def rollback(version) do
    raise ArgumentError,
          "expected migration version as an integer (got: #{inspect(version)})"
  end

  @doc """
  Runs `priv/repo/seeds.exs` in the release, if present.
  """
  def seed do
    load_app()
    seed_script = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_script) do
      Code.eval_file(seed_script)
      :ok
    else
      {:error, :seeds_file_not_found}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp migrations_path do
    Application.app_dir(@app, "priv/repo/migrations")
  end

  defp load_app do
    # Ensures runtime config is loaded so DATABASE_URL, SECRET_KEY_BASE, etc. are available.
    Application.load(@app)

    # Make sure Ecto is available when running via `eval` (which may not boot the app).
    _ = Application.ensure_all_started(:ssl)
    _ = Application.ensure_all_started(:crypto)
    _ = Application.ensure_all_started(:public_key)
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ecto_sql)
    _ = Application.ensure_all_started(:postgrex)

    :ok
  end
end
