defmodule FleetPrompt.Jobs.PackageInstaller do
  @moduledoc """
  Oban worker that installs a package into a tenant.

  This is the Phase 2 "delivery mechanics" worker. It operates on a
  tenant-scoped `FleetPrompt.Packages.Installation` record and installs
  metadata-defined content (currently: Agents) into the tenant schema.

  Design goals:
  - Tenant-safe: all tenant-scoped writes run with `tenant: "org_<slug>"`.
  - Retry-safe: job is retryable; we do best-effort idempotency for created records.
  - Operationally visible: we record failures on the Installation record.

  Notes:
  - Package definitions live in the public schema via `FleetPrompt.Packages.Package`.
  - This worker currently installs agents from `package.includes["agents"]`.
    Workflows/skills are stubbed for forward compatibility.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5

  require Logger
  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Directives.Directive
  alias FleetPrompt.Packages.{Installation, Package}
  alias FleetPrompt.Signals.SignalBus

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"installation_id" => installation_id, "tenant" => tenant}} = job)
      when is_binary(installation_id) and is_binary(tenant) do
    case load_installation(installation_id, tenant) do
      {:ok, %Installation{} = installation} ->
        _ =
          emit_install_signal(
            tenant,
            "package.installation.started",
            %{
              "installation_id" => installation.id,
              "package_slug" => installation.package_slug,
              "package_version" => installation.package_version
            },
            "package_installation_started:#{tenant}:#{installation.id}",
            job
          )

        case mark_installing(installation, tenant) do
          {:ok, %Installation{} = installing} ->
            _ =
              emit_install_signal(
                tenant,
                "package.installation.installing",
                %{
                  "installation_id" => installing.id,
                  "package_slug" => installing.package_slug,
                  "package_version" => installing.package_version,
                  "status" => to_string(installing.status)
                },
                "package_installation_installing:#{tenant}:#{installing.id}",
                job
              )

            case load_package(installing) do
              {:ok, %Package{} = package} ->
                case install_agents(package, tenant) do
                  {:ok, _} ->
                    case install_workflows(package, tenant) do
                      {:ok, _} ->
                        case install_skills(package, tenant) do
                          {:ok, _} ->
                            case mark_installed(installing, tenant) do
                              {:ok, %Installation{} = installed} ->
                                bump_package_stats(package)

                                _ =
                                  maybe_mark_directive_succeeded(installed, tenant, package)

                                _ =
                                  emit_install_signal(
                                    tenant,
                                    "package.installation.installed",
                                    %{
                                      "installation_id" => installed.id,
                                      "package" => %{
                                        "slug" => package.slug,
                                        "version" => package.version
                                      },
                                      "status" => to_string(installed.status),
                                      "installed_at" => installed.installed_at
                                    },
                                    "package_installation_installed:#{tenant}:#{installed.id}",
                                    job
                                  )

                                :ok

                              {:error, reason} ->
                                fail_install(installing, installation_id, tenant, reason)
                            end

                          {:error, reason} ->
                            fail_install(installing, installation_id, tenant, reason)
                        end

                      {:error, reason} ->
                        fail_install(installing, installation_id, tenant, reason)
                    end

                  {:error, reason} ->
                    fail_install(installing, installation_id, tenant, reason)
                end

              {:error, reason} ->
                # Critical: ensure we record the failure even though the installation is already :installing
                fail_install(installing, installation_id, tenant, reason)

              {:discard, reason} ->
                Logger.warning("[PackageInstaller] discarding install", reason: inspect(reason))
                :ok
            end

          {:error, reason} ->
            fail_install(installation, installation_id, tenant, reason)

          {:discard, reason} ->
            Logger.warning("[PackageInstaller] discarding install", reason: inspect(reason))
            :ok
        end

      {:discard, reason} ->
        Logger.warning("[PackageInstaller] discarding install", reason: inspect(reason))
        :ok

      {:error, reason} ->
        msg = normalize_error(reason)

        Logger.warning("[PackageInstaller] install failed; will retry",
          installation_id: installation_id,
          tenant: tenant,
          error: msg
        )

        _ =
          emit_install_signal(
            tenant,
            "package.installation.failed",
            %{
              "installation_id" => installation_id,
              "error" => msg
            },
            "package_installation_failed:#{tenant}:#{installation_id}"
          )

        # Best-effort: record failure on the installation record. If this fails, keep retrying anyway.
        _ = mark_failed_by_id(installation_id, tenant, msg)

        {:error, msg}
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("[PackageInstaller] missing required args", args: inspect(args))
    {:discard, "missing required args: installation_id and tenant"}
  end

  # -----------------------
  # Loading / state updates
  # -----------------------

  defp load_installation(id, tenant) do
    query =
      Installation
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^id))

    case Ash.read_one(query, tenant: tenant) do
      {:ok, %Installation{} = installation} -> {:ok, installation}
      {:ok, nil} -> {:discard, "installation not found"}
      {:error, err} -> {:error, err}
    end
  end

  defp mark_installing(%Installation{} = installation, tenant) do
    installation
    |> Ash.Changeset.for_update(:mark_installing, %{})
    |> Ash.update(tenant: tenant)
  end

  defp mark_installed(%Installation{} = installation, tenant) do
    installation
    |> Ash.Changeset.for_update(:mark_installed, %{})
    |> Ash.update(tenant: tenant)
  end

  defp fail_install(%Installation{} = installation, installation_id, tenant, reason) do
    msg = normalize_error(reason)

    _ =
      emit_install_signal(
        tenant,
        "package.installation.failed",
        %{
          "installation_id" => installation_id,
          "package_slug" => installation.package_slug,
          "package_version" => installation.package_version,
          "status" => to_string(installation.status),
          "error" => msg
        },
        "package_installation_failed:#{tenant}:#{installation_id}"
      )

    _ = mark_failed(installation, tenant, msg)
    _ = mark_failed_by_id(installation_id, tenant, msg)

    _ = maybe_mark_directive_failed(installation, tenant, msg)

    {:error, msg}
  end

  defp mark_failed(%Installation{} = installation, tenant, error_message) do
    installation
    |> Ash.Changeset.for_update(:mark_failed, %{error: error_message})
    |> Ash.update(tenant: tenant)
  end

  defp mark_failed_by_id(id, tenant, error_message) do
    case load_installation(id, tenant) do
      {:ok, %Installation{} = installation} ->
        mark_failed(installation, tenant, error_message)

      _ ->
        :noop
    end
  end

  # -----------------------
  # Package loading
  # -----------------------

  defp load_package(%Installation{} = installation) do
    slug = installation.package_slug
    version = installation.package_version

    if !is_binary(slug) or String.trim(slug) == "" or !is_binary(version) or
         String.trim(version) == "" do
      {:error, "installation missing package identity (package_slug/package_version)"}
    else
      # `by_slug` is get? true, but doesn't constrain version; prefer exact slug+version read.
      # For now, load by slug then verify version in-memory; the seed data expects unique slug anyway.
      query =
        Package
        |> Ash.Query.for_read(:by_slug, %{slug: slug})

      case Ash.read_one(query) do
        {:ok, %Package{} = pkg} ->
          if to_string(pkg.version) == to_string(version) do
            {:ok, pkg}
          else
            {:error,
             "package version mismatch for slug=#{slug}: expected #{version}, got #{pkg.version}"}
          end

        {:ok, nil} ->
          {:error, "package not found (slug=#{slug})"}

        {:error, err} ->
          {:error, err}
      end
    end
  end

  # -----------------------
  # Installers
  # -----------------------

  defp install_agents(%Package{} = package, tenant) do
    if Code.ensure_loaded?(Agent) do
      includes = Map.get(package, :includes) || %{}
      agents = Map.get(includes, "agents") || Map.get(includes, :agents) || []

      agents
      |> List.wrap()
      |> Enum.reduce_while({:ok, 0}, fn agent_spec, {:ok, count} ->
        case install_one_agent(agent_spec, tenant) do
          {:ok, :skipped} -> {:cont, {:ok, count}}
          {:ok, :created} -> {:cont, {:ok, count + 1}}
          {:error, err} -> {:halt, {:error, err}}
        end
      end)
      |> case do
        {:ok, created_count} ->
          Logger.info("[PackageInstaller] installed agents",
            tenant: tenant,
            package: "#{package.slug}@#{package.version}",
            created: created_count
          )

          {:ok, created_count}

        {:error, err} ->
          {:error, err}
      end
    else
      Logger.info("[PackageInstaller] Agent resource not available; skipping agents install")
      {:ok, 0}
    end
  end

  defp install_one_agent(agent_spec, tenant) when is_map(agent_spec) do
    name = Map.get(agent_spec, "name") || Map.get(agent_spec, :name)
    system_prompt = Map.get(agent_spec, "system_prompt") || Map.get(agent_spec, :system_prompt)
    description = Map.get(agent_spec, "description") || Map.get(agent_spec, :description)

    if is_binary(name) and String.trim(name) != "" and is_binary(system_prompt) and
         String.trim(system_prompt) != "" do
      name = String.trim(name)
      system_prompt = String.trim(system_prompt)

      # Best-effort idempotency: skip if an identical agent already exists in this tenant.
      existing_query =
        Agent
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(expr(name == ^name and system_prompt == ^system_prompt))
        |> Ash.Query.limit(1)

      case Ash.read(existing_query, tenant: tenant) do
        {:ok, [%Agent{} | _]} ->
          {:ok, :skipped}

        {:ok, []} ->
          params =
            %{
              name: name,
              description: normalize_optional_string(description),
              system_prompt: system_prompt
            }
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new()

          Agent
          |> Ash.Changeset.for_create(:create, params)
          |> Ash.Changeset.set_tenant(tenant)
          |> Ash.create()
          |> case do
            {:ok, _agent} -> {:ok, :created}
            {:error, err} -> {:error, err}
          end

        {:error, err} ->
          {:error, err}
      end
    else
      Logger.warning("[PackageInstaller] invalid agent spec; skipping",
        agent_spec: inspect(agent_spec)
      )

      {:ok, :skipped}
    end
  end

  defp install_one_agent(_other, _tenant), do: {:ok, :skipped}

  defp install_workflows(%Package{} = package, _tenant) do
    # Workflows are not implemented yet in the codebase (domain placeholder only).
    # Keep this stub so the job stays forward-compatible with Phase 2/3.
    includes = Map.get(package, :includes) || %{}
    workflows = Map.get(includes, "workflows") || Map.get(includes, :workflows) || []

    if workflows != [] do
      Logger.info("[PackageInstaller] workflows install not implemented yet; skipping",
        package: "#{package.slug}@#{package.version}",
        count: length(List.wrap(workflows))
      )
    end

    {:ok, 0}
  end

  defp install_skills(%Package{} = package, _tenant) do
    # Skills are currently global in this repo; per-tenant skill installs are a later phase decision.
    includes = Map.get(package, :includes) || %{}
    skills = Map.get(includes, "skills") || Map.get(includes, :skills) || []

    if skills != [] do
      Logger.info("[PackageInstaller] skills install not implemented yet; skipping",
        package: "#{package.slug}@#{package.version}",
        count: length(List.wrap(skills))
      )
    end

    {:ok, 0}
  end

  # -----------------------
  # Package stats (public schema)
  # -----------------------

  defp bump_package_stats(%Package{} = package) do
    # Best-effort: if this fails, do not fail the install.
    try do
      _ =
        package
        |> Ash.Changeset.for_update(:increment_installs, %{})
        |> Ash.update()

      :ok
    rescue
      err ->
        Logger.warning("[PackageInstaller] failed to increment package installs",
          package: "#{package.slug}@#{package.version}",
          error: Exception.message(err)
        )

        :ok
    catch
      kind, reason ->
        Logger.warning("[PackageInstaller] failed to increment package installs",
          package: "#{package.slug}@#{package.version}",
          error: inspect({kind, reason})
        )

        :ok
    end
  end

  # -----------------------
  # Signals + Directive linkage (Phase 2B)
  # -----------------------

  defp emit_install_signal(tenant, name, payload, dedupe_key, %Oban.Job{} = job)
       when is_binary(tenant) and is_binary(name) and is_map(payload) and is_binary(dedupe_key) do
    emit_install_signal(
      tenant,
      name,
      payload,
      dedupe_key,
      %{
        "oban_job_id" => job.id,
        "oban_attempt" => job.attempt,
        "oban_queue" => job.queue
      }
    )
  end

  defp emit_install_signal(tenant, name, payload, dedupe_key)
       when is_binary(tenant) and is_binary(name) and is_map(payload) and is_binary(dedupe_key) do
    emit_install_signal(tenant, name, payload, dedupe_key, %{})
  end

  defp emit_install_signal(tenant, name, payload, dedupe_key, metadata)
       when is_binary(tenant) and is_binary(name) and is_map(payload) and is_binary(dedupe_key) and
              is_map(metadata) do
    cond do
      not Code.ensure_loaded?(SignalBus) ->
        :noop

      true ->
        # Best-effort only: signals should not break installs if tenant signal migrations
        # haven't been applied yet.
        try do
          _ =
            SignalBus.emit(
              tenant,
              name,
              payload,
              metadata,
              dedupe_key: dedupe_key,
              source: "package_installer"
            )

          :ok
        rescue
          _ -> :noop
        end
    end
  end

  defp maybe_mark_directive_succeeded(
         %Installation{} = installation,
         tenant,
         %Package{} = package
       ) do
    with {:ok, %Directive{} = directive} <- load_directive_for_installation(installation, tenant) do
      result =
        %{
          "type" => "package.install",
          "installation_id" => installation.id,
          "package" => %{"slug" => package.slug, "version" => package.version},
          "status" => "installed"
        }
        |> drop_nils()

      directive
      |> Ash.Changeset.for_update(:mark_succeeded, %{result: result})
      |> Ash.update(tenant: tenant)
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> :noop
      end
    else
      _ -> :noop
    end
  rescue
    _ -> :noop
  end

  defp maybe_mark_directive_failed(%Installation{} = installation, tenant, error_message)
       when is_binary(error_message) do
    with {:ok, %Directive{} = directive} <- load_directive_for_installation(installation, tenant) do
      directive
      |> Ash.Changeset.for_update(:mark_failed, %{error: error_message})
      |> Ash.update(tenant: tenant)
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> :noop
      end
    else
      _ -> :noop
    end
  rescue
    _ -> :noop
  end

  defp maybe_mark_directive_failed(_installation, _tenant, _error_message), do: :noop

  defp load_directive_for_installation(%Installation{} = installation, tenant) do
    key = normalize_optional_string(installation.idempotency_key)

    cond do
      is_nil(key) ->
        {:error, :no_idempotency_key}

      not Code.ensure_loaded?(Directive) ->
        {:error, :directives_not_loaded}

      true ->
        query =
          Directive
          |> Ash.Query.for_read(:by_idempotency_key, %{idempotency_key: key})

        Ash.read_one(query, tenant: tenant)
    end
  end

  defp drop_nils(map) when is_map(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  # -----------------------
  # Small helpers
  # -----------------------

  defp normalize_error(%{__exception__: true} = err), do: Exception.message(err)
  defp normalize_error(err) when is_binary(err), do: err
  defp normalize_error(err), do: inspect(err)

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    v = String.trim(value)
    if v == "", do: nil, else: v
  end

  defp normalize_optional_string(_), do: nil
end
