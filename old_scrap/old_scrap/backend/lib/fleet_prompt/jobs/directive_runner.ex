defmodule FleetPrompt.Jobs.DirectiveRunner do
  @moduledoc """
  Oban worker that executes tenant-scoped **Directives** (Phase 2B).

  Directives are the only allowed path to side effects. This runner:
  - loads a tenant-scoped `FleetPrompt.Directives.Directive`,
  - enforces basic lifecycle guards (scheduled time, terminal states),
  - marks the directive as `:running`,
  - executes based on `directive.name`,
  - marks the directive `:succeeded` or `:failed` with an auditable result/error,
  - optionally emits Signals via `FleetPrompt.Signals.SignalBus` if available.

  v1 scope:
  - `package.install` (delegates to tenant-scoped `Installation` + enqueues `PackageInstaller`)

  Notes:
  - Handlers MUST be idempotent. Oban provides at-least-once execution.
  - This module intentionally does not implement authorization; directives should be
    authorized at request time. Runner assumes the directive is valid for the tenant.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  require Logger
  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Directives.Directive
  alias FleetPrompt.Forums.{Post, Thread}
  alias FleetPrompt.Packages.{Installation, Package}
  alias FleetPrompt.Jobs.PackageInstaller

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"directive_id" => directive_id, "tenant" => tenant} = args} = job)
      when is_binary(directive_id) and is_binary(tenant) do
    with {:ok, %Directive{} = directive} <- load_directive(directive_id, tenant),
         :ok <- ensure_due(directive),
         :ok <- ensure_runnable(directive, args),
         {:ok, %Directive{} = running} <- mark_running_and_bump_attempt(directive, tenant, job),
         result <- execute(running, tenant, args, job),
         {:ok, %Directive{} = _final} <- finalize(running, tenant, result, job) do
      :ok
    else
      {:snooze, seconds} ->
        {:snooze, seconds}

      {:discard, reason} ->
        Logger.warning("[DirectiveRunner] discarding job",
          tenant: tenant,
          directive_id: directive_id,
          reason: reason
        )

        :ok

      {:ok, :noop} ->
        :ok

      {:error, err} ->
        msg = normalize_error(err)

        Logger.warning("[DirectiveRunner] directive execution failed; will retry",
          tenant: tenant,
          directive_id: directive_id,
          error: msg
        )

        {:error, msg}
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("[DirectiveRunner] missing required args", args: inspect(args))
    {:discard, "missing required args: directive_id and tenant"}
  end

  # -----------------------
  # Loading / guards
  # -----------------------

  defp load_directive(id, tenant) do
    query =
      Directive
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^id))

    case Ash.read_one(query, tenant: tenant) do
      {:ok, %Directive{} = directive} -> {:ok, directive}
      {:ok, nil} -> {:discard, "directive not found"}
      {:error, err} -> {:error, err}
    end
  end

  defp ensure_due(%Directive{} = directive) do
    case directive.scheduled_at do
      %DateTime{} = scheduled_at ->
        now = DateTime.utc_now()
        diff = DateTime.diff(scheduled_at, now, :second)

        if diff > 0 do
          # Oban supports snoozing. Keep it bounded so the job wakes up reasonably soon.
          {:snooze, min(diff, 60)}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp ensure_runnable(%Directive{} = directive, args) when is_map(args) do
    case directive.status do
      s when s in [:succeeded, :canceled] ->
        # Terminal by default. Allow explicit rerun only when requested.
        if truthy_rerun?(args) do
          :ok
        else
          {:discard, "directive is already in a terminal state: #{s}"}
        end

      :failed ->
        # Safety: failed directives are terminal by default so Oban retries don't
        # re-run side effects. To re-run a failed directive, explicitly re-enqueue
        # with args.rerun=true (or args.force=true).
        if truthy_rerun?(args) do
          :ok
        else
          {:discard, "directive is failed (set args.rerun=true to run again)"}
        end

      :running ->
        # If a job is retried while the directive is still marked running,
        # discard so we don't race or double-execute.
        {:discard, "directive is already running"}

      _ ->
        :ok
    end
  end

  defp ensure_runnable(%Directive{} = directive, _args) do
    ensure_runnable(directive, %{})
  end

  defp truthy_rerun?(args) when is_map(args) do
    truthy?(Map.get(args, "rerun")) or truthy?(Map.get(args, :rerun)) or
      truthy?(Map.get(args, "force")) or truthy?(Map.get(args, :force))
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false

  defp mark_running_and_bump_attempt(%Directive{} = directive, tenant, job) do
    # We want an auditable attempt bump even if execution fails early.
    # The order here is:
    # 1) bump attempt
    # 2) mark running
    # 3) emit signal
    #
    # NOTE: These are separate updates (non-atomic). For v1, this is acceptable.
    # Phase 2B hardening can introduce transaction semantics if needed.
    with {:ok, %Directive{} = bumped} <-
           directive
           |> Ash.Changeset.for_update(:bump_attempt, %{})
           |> Ash.update(tenant: tenant),
         {:ok, %Directive{} = running} <-
           bumped
           |> Ash.Changeset.for_update(:mark_running, %{})
           |> Ash.update(tenant: tenant) do
      emit_lifecycle_signal_maybe(
        tenant,
        "directive.started",
        %{
          "directive_id" => running.id,
          "directive_name" => running.name,
          "attempt" => running.attempt,
          "oban_job_id" => job.id
        },
        running
      )

      {:ok, running}
    end
  end

  # -----------------------
  # Execution dispatch
  # -----------------------

  defp execute(%Directive{} = directive, tenant, _args, _job) do
    name = to_string(directive.name || "")

    case name do
      "package.install" ->
        execute_package_install(directive, tenant)

      "package.uninstall" ->
        execute_package_uninstall(directive, tenant)

      # Forums (Phase 2C lighthouse): moderation directives (must be directive-backed)
      "forum.thread.lock" ->
        execute_forum_thread_lock(directive, tenant)

      "forum.thread.unlock" ->
        execute_forum_thread_unlock(directive, tenant)

      "forum.post.hide" ->
        execute_forum_post_hide(directive, tenant)

      "forum.post.unhide" ->
        execute_forum_post_unhide(directive, tenant)

      "forum.post.delete" ->
        execute_forum_post_delete(directive, tenant)

      other when is_binary(other) and other != "" ->
        {:error, "unsupported directive: #{other}"}

      _ ->
        {:error, "directive name is missing"}
    end
  end

  # -----------------------
  # Directive: package.install
  # -----------------------

  defp execute_package_install(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    slug =
      payload
      |> Map.get("slug", Map.get(payload, :slug))
      |> normalize_string()

    requested_version =
      payload
      |> Map.get("version", Map.get(payload, :version))
      |> normalize_optional_string()

    config =
      case Map.get(payload, "config", Map.get(payload, :config)) do
        %{} = cfg -> cfg
        _ -> %{}
      end

    cond do
      is_nil(slug) ->
        {:error, "package.install requires payload.slug"}

      not Code.ensure_loaded?(Package) ->
        {:error, "package registry is not available"}

      not Code.ensure_loaded?(Installation) ->
        {:error, "package installations are not available"}

      not Code.ensure_loaded?(PackageInstaller) ->
        {:error, "package installer worker is not available"}

      true ->
        with {:ok, %Package{} = pkg} <- load_package_by_slug(slug),
             :ok <- ensure_package_version_matches(pkg, requested_version),
             :ok <- ensure_package_published(pkg),
             {:ok, %Installation{} = installation, installation_marker} <-
               get_or_create_installation(pkg, tenant, directive, config),
             {:ok, enqueue_marker} <- maybe_enqueue_package_installer(installation, tenant) do
          emit_domain_signal_maybe(
            tenant,
            "package.install.processed",
            %{
              "directive_id" => directive.id,
              "package" => %{"slug" => pkg.slug, "version" => pkg.version},
              "installation" => %{
                "id" => installation.id,
                "status" => installation.status,
                "created" => installation_marker == :created
              },
              "enqueued" => enqueue_marker == :enqueued
            },
            directive,
            %{type: "package.installation", id: to_string(installation.id)},
            "package.install.processed:#{tenant}:#{installation.id}:#{directive.id}"
          )
          |> ignore()

          {:ok,
           %{
             "type" => "package.install",
             "package" => %{"slug" => pkg.slug, "version" => pkg.version},
             "installation_id" => installation.id,
             "installation_status" => installation.status,
             "installation_created" => installation_marker == :created,
             "enqueued" => enqueue_marker == :enqueued,
             "tenant" => tenant
           }}
        end
    end
  end

  # -----------------------
  # Directive: package.uninstall
  # -----------------------
  #
  # v1 semantics:
  # - This is primarily an *operational* uninstall (so you can re-run installs).
  # - It destroys the tenant-scoped Installation record so a subsequent install can create a fresh one.
  # - Optionally purges installed Agents that match the package "includes" signature (name + system_prompt).
  #
  # NOTE:
  # This does NOT attempt to delete workflows/skills/etc. yet, because we don't have robust per-package
  # provenance tracking. Installer idempotency should prevent duplication on reinstall.
  defp execute_package_uninstall(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    slug =
      payload
      |> Map.get("slug", Map.get(payload, :slug))
      |> normalize_string()

    requested_version =
      payload
      |> Map.get("version", Map.get(payload, :version))
      |> normalize_optional_string()

    purge? =
      truthy?(Map.get(payload, "purge")) or truthy?(Map.get(payload, :purge)) or
        truthy?(Map.get(payload, "purge_agents")) or truthy?(Map.get(payload, :purge_agents)) or
        truthy?(Map.get(payload, "purge_content")) or truthy?(Map.get(payload, :purge_content))

    cond do
      is_nil(slug) ->
        {:error, "package.uninstall requires payload.slug"}

      not Code.ensure_loaded?(Installation) ->
        {:error, "package installations are not available"}

      true ->
        case load_installation_by_slug(slug, tenant) do
          {:ok, nil} ->
            {:ok,
             %{
               "type" => "package.uninstall",
               "package" => %{"slug" => slug, "version" => requested_version},
               "installation_removed" => false,
               "purged_agents" => 0,
               "reason" => "not_installed",
               "tenant" => tenant
             }}

          {:ok, %Installation{} = installation} ->
            if is_binary(requested_version) and
                 to_string(installation.package_version) != requested_version do
              {:error,
               "package version mismatch for uninstall slug=#{slug}: expected #{installation.package_version}, got #{requested_version}"}
            else
              purged_agents =
                if purge? do
                  purge_package_agents_best_effort(tenant, slug, installation.package_version)
                else
                  0
                end

              installation
              |> Ash.Changeset.for_destroy(:destroy, %{})
              |> Ash.destroy(tenant: tenant)
              |> case do
                :ok ->
                  emit_domain_signal_maybe(
                    tenant,
                    "package.uninstall.processed",
                    %{
                      "directive_id" => directive.id,
                      "package" => %{
                        "slug" => slug,
                        "version" => installation.package_version
                      },
                      "installation_removed" => true,
                      "purged_agents" => purged_agents
                    },
                    directive,
                    %{type: "package.installation", id: to_string(installation.id)},
                    "package.uninstall.processed:#{tenant}:#{installation.id}:#{directive.id}"
                  )
                  |> ignore()

                  {:ok,
                   %{
                     "type" => "package.uninstall",
                     "package" => %{"slug" => slug, "version" => installation.package_version},
                     "installation_removed" => true,
                     "purged_agents" => purged_agents,
                     "tenant" => tenant
                   }}

                {:ok, _} ->
                  emit_domain_signal_maybe(
                    tenant,
                    "package.uninstall.processed",
                    %{
                      "directive_id" => directive.id,
                      "package" => %{
                        "slug" => slug,
                        "version" => installation.package_version
                      },
                      "installation_removed" => true,
                      "purged_agents" => purged_agents
                    },
                    directive,
                    %{type: "package.installation", id: to_string(installation.id)},
                    "package.uninstall.processed:#{tenant}:#{installation.id}:#{directive.id}"
                  )
                  |> ignore()

                  {:ok,
                   %{
                     "type" => "package.uninstall",
                     "package" => %{"slug" => slug, "version" => installation.package_version},
                     "installation_removed" => true,
                     "purged_agents" => purged_agents,
                     "tenant" => tenant
                   }}

                {:error, err} ->
                  {:error, err}
              end
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp load_installation_by_slug(slug, tenant) when is_binary(slug) and is_binary(tenant) do
    query =
      Installation
      |> Ash.Query.for_read(:by_slug, %{package_slug: slug})

    Ash.read_one(query, tenant: tenant)
  end

  defp purge_package_agents_best_effort(tenant, slug, version)
       when is_binary(tenant) and is_binary(slug) do
    # Best-effort only: if anything goes wrong (package missing, agent read fails, etc.)
    # we return 0 to keep uninstall resilient.
    if Code.ensure_loaded?(Agent) and Code.ensure_loaded?(Package) do
      case load_package_by_slug(slug) do
        {:ok, %Package{} = pkg} ->
          if is_binary(version) and to_string(pkg.version) != to_string(version) do
            0
          else
            includes = Map.get(pkg, :includes) || %{}
            agent_specs = Map.get(includes, "agents") || Map.get(includes, :agents) || []

            signatures =
              agent_specs
              |> List.wrap()
              |> Enum.filter(&is_map/1)
              |> Enum.map(fn spec ->
                name = Map.get(spec, "name") || Map.get(spec, :name)
                system_prompt = Map.get(spec, "system_prompt") || Map.get(spec, :system_prompt)

                if is_binary(name) and is_binary(system_prompt) do
                  {String.trim(name), String.trim(system_prompt)}
                else
                  nil
                end
              end)
              |> Enum.reject(&is_nil/1)

            if signatures == [] do
              0
            else
              case Ash.read(Agent, tenant: tenant) do
                {:ok, agents} when is_list(agents) ->
                  agents
                  |> Enum.filter(fn a ->
                    Enum.any?(signatures, fn {n, sp} -> a.name == n and a.system_prompt == sp end)
                  end)
                  |> Enum.reduce(0, fn agent, acc ->
                    case Ash.destroy(agent, tenant: tenant) do
                      {:ok, _} -> acc + 1
                      {:error, _} -> acc
                    end
                  end)

                _ ->
                  0
              end
            end
          end

        _ ->
          0
      end
    else
      0
    end
  rescue
    _ -> 0
  end

  defp load_package_by_slug(slug) when is_binary(slug) do
    query =
      Package
      |> Ash.Query.for_read(:by_slug, %{slug: slug})

    case Ash.read_one(query) do
      {:ok, %Package{} = pkg} -> {:ok, pkg}
      {:ok, nil} -> {:error, "package not found (slug=#{slug})"}
      {:error, err} -> {:error, err}
    end
  end

  defp ensure_package_version_matches(_pkg, nil), do: :ok

  defp ensure_package_version_matches(%Package{} = pkg, requested_version)
       when is_binary(requested_version) do
    if to_string(pkg.version) == requested_version do
      :ok
    else
      {:error,
       "package version mismatch for slug=#{pkg.slug}: expected #{pkg.version}, got #{requested_version}"}
    end
  end

  defp ensure_package_published(%Package{} = pkg) do
    if Map.get(pkg, :is_published) == true do
      :ok
    else
      {:error, :not_published}
    end
  end

  defp get_or_create_installation(%Package{} = pkg, tenant, %Directive{} = directive, config) do
    existing_query =
      Installation
      |> Ash.Query.for_read(:by_slug, %{package_slug: pkg.slug})

    case Ash.read_one(existing_query, tenant: tenant) do
      {:ok, %Installation{} = existing} ->
        {:ok, existing, :existing}

      {:ok, nil} ->
        installed_by_user_id =
          directive.requested_by_user_id ||
            Map.get(directive.metadata || %{}, "requested_by_user_id") ||
            Map.get(directive.metadata || %{}, :requested_by_user_id)
            |> normalize_optional_string()

        changeset =
          Installation
          |> Ash.Changeset.for_create(:request_install, %{
            package_slug: pkg.slug,
            package_version: pkg.version,
            package_name: pkg.name,
            installed_by_user_id: installed_by_user_id,
            config: config || %{},
            idempotency_key: directive.idempotency_key
          })
          |> Ash.Changeset.set_tenant(tenant)

        case Ash.create(changeset) do
          {:ok, %Installation{} = created} -> {:ok, created, :created}
          {:error, err} -> {:error, err}
        end

      {:error, err} ->
        {:error, err}
    end
  end

  defp maybe_enqueue_package_installer(%Installation{} = installation, tenant) do
    case installation.status do
      :installed -> {:ok, :skipped}
      :installing -> {:ok, :skipped}
      :disabled -> {:ok, :skipped}
      _ -> enqueue_package_installer(installation.id, tenant)
    end
  end

  defp enqueue_package_installer(installation_id, tenant) do
    job =
      PackageInstaller.new(%{
        "installation_id" => installation_id,
        "tenant" => tenant
      })

    case Oban.insert(job) do
      {:ok, _job} -> {:ok, :enqueued}
      {:error, err} -> {:error, err}
    end
  end

  # -----------------------
  # Forums moderation directives (Phase 2C lighthouse)
  # -----------------------

  defp execute_forum_thread_lock(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    thread_id =
      payload
      |> Map.get("thread_id", Map.get(payload, :thread_id))
      |> normalize_string()

    cond do
      is_nil(thread_id) ->
        {:error, "forum.thread.lock requires payload.thread_id"}

      not Code.ensure_loaded?(Thread) ->
        {:error, "forums threads are not available"}

      true ->
        case load_forum_thread_by_id(thread_id, tenant) do
          {:ok, nil} ->
            {:error, "thread not found"}

          {:ok, %Thread{} = thread} ->
            case thread |> Ash.Changeset.for_update(:lock, %{}) |> Ash.update(tenant: tenant) do
              {:ok, %Thread{} = updated} ->
                _ =
                  emit_domain_signal_maybe(
                    tenant,
                    "forum.thread.locked",
                    %{
                      "thread_id" => updated.id,
                      "status" => to_string(updated.status)
                    },
                    directive,
                    %{type: "forum.thread", id: to_string(updated.id)},
                    "forum.thread.locked:#{tenant}:#{updated.id}:#{directive.id}"
                  )

                {:ok,
                 %{
                   "type" => "forum.thread.lock",
                   "thread_id" => updated.id,
                   "status" => to_string(updated.status),
                   "tenant" => tenant
                 }}

              {:error, err} ->
                {:error, err}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp execute_forum_thread_unlock(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    thread_id =
      payload
      |> Map.get("thread_id", Map.get(payload, :thread_id))
      |> normalize_string()

    cond do
      is_nil(thread_id) ->
        {:error, "forum.thread.unlock requires payload.thread_id"}

      not Code.ensure_loaded?(Thread) ->
        {:error, "forums threads are not available"}

      true ->
        case load_forum_thread_by_id(thread_id, tenant) do
          {:ok, nil} ->
            {:error, "thread not found"}

          {:ok, %Thread{} = thread} ->
            case thread |> Ash.Changeset.for_update(:unlock, %{}) |> Ash.update(tenant: tenant) do
              {:ok, %Thread{} = updated} ->
                _ =
                  emit_domain_signal_maybe(
                    tenant,
                    "forum.thread.unlocked",
                    %{
                      "thread_id" => updated.id,
                      "status" => to_string(updated.status)
                    },
                    directive,
                    %{type: "forum.thread", id: to_string(updated.id)},
                    "forum.thread.unlocked:#{tenant}:#{updated.id}:#{directive.id}"
                  )

                {:ok,
                 %{
                   "type" => "forum.thread.unlock",
                   "thread_id" => updated.id,
                   "status" => to_string(updated.status),
                   "tenant" => tenant
                 }}

              {:error, err} ->
                {:error, err}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp execute_forum_post_hide(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    post_id =
      payload
      |> Map.get("post_id", Map.get(payload, :post_id))
      |> normalize_string()

    cond do
      is_nil(post_id) ->
        {:error, "forum.post.hide requires payload.post_id"}

      not Code.ensure_loaded?(Post) ->
        {:error, "forums posts are not available"}

      true ->
        case load_forum_post_by_id(post_id, tenant) do
          {:ok, nil} ->
            {:error, "post not found"}

          {:ok, %Post{} = post} ->
            case post |> Ash.Changeset.for_update(:hide, %{}) |> Ash.update(tenant: tenant) do
              {:ok, %Post{} = updated} ->
                _ =
                  emit_domain_signal_maybe(
                    tenant,
                    "forum.post.hidden",
                    %{
                      "post_id" => updated.id,
                      "thread_id" => updated.thread_id,
                      "status" => to_string(updated.status)
                    },
                    directive,
                    %{type: "forum.post", id: to_string(updated.id)},
                    "forum.post.hidden:#{tenant}:#{updated.id}:#{directive.id}"
                  )

                {:ok,
                 %{
                   "type" => "forum.post.hide",
                   "post_id" => updated.id,
                   "thread_id" => updated.thread_id,
                   "status" => to_string(updated.status),
                   "tenant" => tenant
                 }}

              {:error, err} ->
                {:error, err}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp execute_forum_post_unhide(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    post_id =
      payload
      |> Map.get("post_id", Map.get(payload, :post_id))
      |> normalize_string()

    cond do
      is_nil(post_id) ->
        {:error, "forum.post.unhide requires payload.post_id"}

      not Code.ensure_loaded?(Post) ->
        {:error, "forums posts are not available"}

      true ->
        case load_forum_post_by_id(post_id, tenant) do
          {:ok, nil} ->
            {:error, "post not found"}

          {:ok, %Post{} = post} ->
            case post |> Ash.Changeset.for_update(:unhide, %{}) |> Ash.update(tenant: tenant) do
              {:ok, %Post{} = updated} ->
                _ =
                  emit_domain_signal_maybe(
                    tenant,
                    "forum.post.unhidden",
                    %{
                      "post_id" => updated.id,
                      "thread_id" => updated.thread_id,
                      "status" => to_string(updated.status)
                    },
                    directive,
                    %{type: "forum.post", id: to_string(updated.id)},
                    "forum.post.unhidden:#{tenant}:#{updated.id}:#{directive.id}"
                  )

                {:ok,
                 %{
                   "type" => "forum.post.unhide",
                   "post_id" => updated.id,
                   "thread_id" => updated.thread_id,
                   "status" => to_string(updated.status),
                   "tenant" => tenant
                 }}

              {:error, err} ->
                {:error, err}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp execute_forum_post_delete(%Directive{} = directive, tenant) do
    payload = directive.payload || %{}

    post_id =
      payload
      |> Map.get("post_id", Map.get(payload, :post_id))
      |> normalize_string()

    cond do
      is_nil(post_id) ->
        {:error, "forum.post.delete requires payload.post_id"}

      not Code.ensure_loaded?(Post) ->
        {:error, "forums posts are not available"}

      true ->
        case load_forum_post_by_id(post_id, tenant) do
          {:ok, nil} ->
            {:error, "post not found"}

          {:ok, %Post{} = post} ->
            case post |> Ash.Changeset.for_update(:delete, %{}) |> Ash.update(tenant: tenant) do
              {:ok, %Post{} = updated} ->
                _ =
                  emit_domain_signal_maybe(
                    tenant,
                    "forum.post.deleted",
                    %{
                      "post_id" => updated.id,
                      "thread_id" => updated.thread_id,
                      "status" => to_string(updated.status)
                    },
                    directive,
                    %{type: "forum.post", id: to_string(updated.id)},
                    "forum.post.deleted:#{tenant}:#{updated.id}:#{directive.id}"
                  )

                {:ok,
                 %{
                   "type" => "forum.post.delete",
                   "post_id" => updated.id,
                   "thread_id" => updated.thread_id,
                   "status" => to_string(updated.status),
                   "tenant" => tenant
                 }}

              {:error, err} ->
                {:error, err}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp load_forum_thread_by_id(thread_id, tenant) when is_binary(tenant) do
    query =
      Thread
      |> Ash.Query.for_read(:by_id, %{id: thread_id})

    Ash.read_one(query, tenant: tenant)
  end

  defp load_forum_post_by_id(post_id, tenant) when is_binary(tenant) do
    query =
      Post
      |> Ash.Query.for_read(:by_id, %{id: post_id})

    Ash.read_one(query, tenant: tenant)
  end

  # -----------------------
  # Finalization
  # -----------------------

  defp finalize(%Directive{} = directive, tenant, {:ok, %{} = result}, job) do
    emit_lifecycle_signal_maybe(
      tenant,
      "directive.succeeded",
      %{
        "directive_id" => directive.id,
        "directive_name" => directive.name,
        "attempt" => directive.attempt,
        "oban_job_id" => job.id
      },
      directive
    )
    |> ignore()

    directive
    |> Ash.Changeset.for_update(:mark_succeeded, %{result: result})
    |> Ash.update(tenant: tenant)
  end

  defp finalize(%Directive{} = directive, tenant, {:error, err}, job) do
    msg = normalize_error(err)

    emit_lifecycle_signal_maybe(
      tenant,
      "directive.failed",
      %{
        "directive_id" => directive.id,
        "directive_name" => directive.name,
        "attempt" => directive.attempt,
        "oban_job_id" => job.id,
        "error" => msg
      },
      directive
    )
    |> ignore()

    directive
    |> Ash.Changeset.for_update(:mark_failed, %{error: msg})
    |> Ash.update(tenant: tenant)
    |> case do
      {:ok, %Directive{} = _failed} -> {:error, msg}
      {:error, update_err} -> {:error, update_err}
    end
  end

  defp finalize(_directive, _tenant, other, _job) do
    {:error, "unexpected directive handler return: #{inspect(other)}"}
  end

  # -----------------------
  # Lifecycle Signals (optional, but should include actor/subject context)
  # -----------------------

  defp emit_lifecycle_signal_maybe(tenant, name, payload, %Directive{} = directive)
       when is_binary(tenant) and is_binary(name) and is_map(payload) do
    # Keep the runner resilient if signals aren't migrated/available yet.
    cond do
      not Code.ensure_loaded?(FleetPrompt.Signals.SignalBus) ->
        :noop

      true ->
        actor = lifecycle_actor(directive)
        subject = lifecycle_subject(directive)

        dedupe_key =
          "directive_runner:#{tenant}:#{name}:#{directive.id}:" <>
            "#{directive.attempt || 0}"

        # Best-effort. If signals fail (e.g., missing tenant migration), don't fail the directive.
        try do
          _ =
            FleetPrompt.Signals.SignalBus.emit(
              tenant,
              name,
              payload,
              %{},
              dedupe_key: dedupe_key,
              actor: actor,
              subject: subject,
              source: "directive_runner"
            )

          :ok
        rescue
          _ -> :noop
        end
    end
  end

  defp emit_lifecycle_signal_maybe(_tenant, _name, _payload, _directive), do: :noop

  defp lifecycle_actor(%Directive{} = directive) do
    case directive.requested_by_user_id do
      nil -> nil
      id -> %{type: "user", id: to_string(id)}
    end
  end

  defp lifecycle_subject(%Directive{} = directive) do
    payload = directive.payload || %{}

    # Allow explicit subject override in payload
    explicit = Map.get(payload, "subject") || Map.get(payload, :subject)

    cond do
      is_map(explicit) and is_binary(Map.get(explicit, "type")) and
          is_binary(Map.get(explicit, "id")) ->
        %{
          type: Map.get(explicit, "type") |> normalize_optional_string(),
          id: Map.get(explicit, "id") |> normalize_optional_string()
        }

      is_map(explicit) and is_binary(Map.get(explicit, :type)) and
          not is_nil(Map.get(explicit, :id)) ->
        %{
          type: Map.get(explicit, :type) |> normalize_optional_string(),
          id: Map.get(explicit, :id) |> to_string() |> normalize_optional_string()
        }

      true ->
        thread_id =
          Map.get(payload, "thread_id") ||
            Map.get(payload, :thread_id) ||
            Map.get(payload, "threadId") ||
            Map.get(payload, :threadId)

        post_id =
          Map.get(payload, "post_id") ||
            Map.get(payload, :post_id) ||
            Map.get(payload, "postId") ||
            Map.get(payload, :postId)

        installation_id =
          Map.get(payload, "installation_id") ||
            Map.get(payload, :installation_id) ||
            Map.get(payload, "installationId") ||
            Map.get(payload, :installationId)

        slug = Map.get(payload, "slug") || Map.get(payload, :slug)

        cond do
          is_binary(thread_id) and String.trim(thread_id) != "" ->
            %{type: "forum.thread", id: String.trim(thread_id)}

          is_binary(post_id) and String.trim(post_id) != "" ->
            %{type: "forum.post", id: String.trim(post_id)}

          is_binary(installation_id) and String.trim(installation_id) != "" ->
            %{type: "package.installation", id: String.trim(installation_id)}

          is_binary(slug) and String.trim(slug) != "" ->
            %{type: "package", id: String.trim(slug)}

          true ->
            nil
        end
    end
  end

  defp lifecycle_subject(_), do: nil

  defp emit_domain_signal_maybe(
         tenant,
         name,
         payload,
         %Directive{} = directive,
         subject,
         dedupe_key
       )
       when is_binary(tenant) and is_binary(name) and is_map(payload) and is_binary(dedupe_key) do
    cond do
      not Code.ensure_loaded?(FleetPrompt.Signals.SignalBus) ->
        :noop

      true ->
        actor = lifecycle_actor(directive)

        try do
          _ =
            FleetPrompt.Signals.SignalBus.emit(
              tenant,
              name,
              payload,
              %{},
              dedupe_key: dedupe_key,
              actor: actor,
              subject: subject,
              source: "directive_runner"
            )

          :ok
        rescue
          _ -> :noop
        end
    end
  end

  defp emit_domain_signal_maybe(_tenant, _name, _payload, _directive, _subject, _dedupe_key),
    do: :noop

  # -----------------------
  # Helpers
  # -----------------------

  defp normalize_error(%{__exception__: true} = err), do: Exception.message(err)
  defp normalize_error(err) when is_binary(err), do: err
  defp normalize_error(err), do: inspect(err)

  defp normalize_string(nil), do: nil

  defp normalize_string(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      s -> s
    end
  end

  defp normalize_string(v), do: v |> to_string() |> normalize_string()

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      s -> s
    end
  end

  defp normalize_optional_string(v), do: v |> to_string() |> normalize_optional_string()

  defp ignore(_), do: :ok
end
