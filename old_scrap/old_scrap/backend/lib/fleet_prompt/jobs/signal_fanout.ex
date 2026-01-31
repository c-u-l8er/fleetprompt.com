defmodule FleetPrompt.Jobs.SignalFanout do
  @moduledoc """
  Oban worker that *fans out* a persisted Signal to configured handlers (Phase 2B).

  ## Why this exists

  - Signals are durable facts (persisted in tenant schemas).
  - Side effects and downstream processing should happen via **durable fanout**, not
    inline at the point of signal emission.
  - This job provides "at least once" delivery to handlers (handlers must be idempotent).

  ## Handler configuration

  Configure handlers via application env:

      config :fleet_prompt, :signal_handlers, [
        FleetPrompt.SomeHandler,
        {FleetPrompt.OtherHandler, foo: :bar}
      ]

  Each handler module should export one of:

  - `handle_signal(signal, context)` or
  - `handle_signal(signal, tenant, context)` or
  - `handle_signal(signal)` (discouraged; kept for flexibility)

  Where:
  - `signal` is `%FleetPrompt.Signals.Signal{}` (tenant-scoped record)
  - `tenant` is the tenant schema name (e.g. `"org_demo"`)
  - `context` is a map containing metadata like args/job ids

  ## Semantics

  - If no handlers are configured, this job is a no-op and returns `:ok`.
  - Handlers are invoked in order.
  - If a handler returns `{:error, reason}` or raises, the job fails and will be retried by Oban.
  - If a handler returns `:ok` or `{:ok, _}`, processing continues.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  require Logger
  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  alias FleetPrompt.Signals.Signal

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"signal_id" => signal_id, "tenant" => tenant} = args} = job)
      when is_binary(signal_id) and is_binary(tenant) do
    with {:ok, %Signal{} = signal} <- load_signal(signal_id, tenant) do
      handlers = configured_handlers()

      if handlers == [] do
        Logger.debug("[SignalFanout] no handlers configured; skipping",
          tenant: tenant,
          signal_id: signal.id,
          signal_name: signal.name
        )

        :ok
      else
        context = build_context(job, tenant, signal, args)

        Logger.debug("[SignalFanout] dispatching signal to handlers",
          tenant: tenant,
          signal_id: signal.id,
          signal_name: signal.name,
          handler_count: length(handlers)
        )

        Enum.reduce_while(handlers, :ok, fn handler_spec, :ok ->
          {mod, opts} = normalize_handler_spec(handler_spec)

          case invoke_handler(mod, signal, tenant, context, opts) do
            :ok ->
              {:cont, :ok}

            {:ok, _} ->
              {:cont, :ok}

            {:error, reason} ->
              Logger.warning("[SignalFanout] handler returned error",
                tenant: tenant,
                signal_id: signal.id,
                signal_name: signal.name,
                handler: inspect(mod),
                error: normalize_error(reason)
              )

              {:halt, {:error, normalize_error(reason)}}
          end
        end)
      end
    else
      {:discard, reason} ->
        Logger.warning("[SignalFanout] discarding job",
          reason: reason,
          tenant: tenant,
          signal_id: signal_id
        )

        :ok

      {:ok, nil} ->
        Logger.warning("[SignalFanout] discarding job; signal not found",
          tenant: tenant,
          signal_id: signal_id
        )

        :ok

      {:error, err} ->
        msg = normalize_error(err)

        Logger.warning("[SignalFanout] failed to load signal; will retry",
          tenant: tenant,
          signal_id: signal_id,
          error: msg
        )

        {:error, msg}
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("[SignalFanout] missing required args", args: inspect(args))
    {:discard, "missing required args: signal_id and tenant"}
  end

  # -----------------------
  # Loading
  # -----------------------

  defp load_signal(signal_id, tenant) do
    query =
      Signal
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^signal_id))

    case Ash.read_one(query, tenant: tenant) do
      {:ok, %Signal{} = signal} -> {:ok, signal}
      {:ok, nil} -> {:discard, "signal not found"}
      {:error, err} -> {:error, err}
    end
  end

  # -----------------------
  # Handlers
  # -----------------------

  defp configured_handlers do
    Application.get_env(:fleet_prompt, :signal_handlers, [])
    |> List.wrap()
    |> Enum.filter(fn
      mod when is_atom(mod) -> true
      {mod, _opts} when is_atom(mod) -> true
      _ -> false
    end)
  end

  defp normalize_handler_spec(mod) when is_atom(mod), do: {mod, []}
  defp normalize_handler_spec({mod, opts}) when is_atom(mod) and is_list(opts), do: {mod, opts}

  defp normalize_handler_spec({mod, opts}) when is_atom(mod) and is_map(opts),
    do: {mod, Map.to_list(opts)}

  defp normalize_handler_spec(other), do: {other, []}

  defp invoke_handler(mod, signal, tenant, context, opts) when is_atom(mod) do
    cond do
      function_exported?(mod, :handle_signal, 3) ->
        safe_invoke(fn ->
          mod.handle_signal(signal, tenant, Map.put(context, :handler_opts, opts))
        end)

      function_exported?(mod, :handle_signal, 2) ->
        safe_invoke(fn -> mod.handle_signal(signal, Map.put(context, :handler_opts, opts)) end)

      function_exported?(mod, :handle_signal, 1) ->
        safe_invoke(fn -> mod.handle_signal(signal) end)

      true ->
        Logger.debug("[SignalFanout] handler does not export handle_signal/*; skipping",
          tenant: tenant,
          signal_id: signal.id,
          signal_name: signal.name,
          handler: inspect(mod)
        )

        :ok
    end
  end

  defp invoke_handler(mod, signal, tenant, _context, _opts) do
    Logger.debug("[SignalFanout] invalid handler spec; skipping",
      tenant: tenant,
      signal_id: signal.id,
      signal_name: signal.name,
      handler: inspect(mod)
    )

    :ok
  end

  defp safe_invoke(fun) when is_function(fun, 0) do
    fun.()
  rescue
    err ->
      {:error, Exception.message(err)}
  catch
    kind, value ->
      {:error, "#{inspect(kind)}: #{inspect(value)}"}
  end

  # -----------------------
  # Context
  # -----------------------

  defp build_context(%Oban.Job{} = job, tenant, %Signal{} = signal, args) do
    %{
      tenant: tenant,
      signal_id: signal.id,
      signal_name: signal.name,
      dedupe_key: signal.dedupe_key,
      correlation_id: signal.correlation_id,
      causation_id: signal.causation_id,
      source: signal.source,
      occurred_at: signal.occurred_at,
      inserted_at: signal.inserted_at,
      oban: %{
        job_id: job.id,
        attempt: job.attempt,
        max_attempts: job.max_attempts,
        queue: job.queue
      },
      args: args
    }
  end

  # -----------------------
  # Error helpers
  # -----------------------

  defp normalize_error(%{__exception__: true} = err), do: Exception.message(err)
  defp normalize_error(err) when is_binary(err), do: err
  defp normalize_error(err), do: inspect(err)
end
