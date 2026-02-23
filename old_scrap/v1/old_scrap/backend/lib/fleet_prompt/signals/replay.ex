defmodule FleetPrompt.Signals.Replay do
  @moduledoc """
  Minimal Signal replay helper (Phase 2B).

  This module re-enqueues fanout jobs for already-persisted tenant Signals.

  ## Why this exists

  - Signals are durable facts (tenant-scoped rows).
  - Handlers may be added/changed over time.
  - Replay lets you re-run handler fanout deterministically and durably via Oban.

  ## What this does (and doesn't do)

  - ✅ Re-enqueues `FleetPrompt.Jobs.SignalFanout` jobs for matching signals.
  - ✅ Provides a few ergonomic query helpers (recent/by_name/by_ids/by_time_range).
  - ✅ Safe no-op if Oban or the fanout worker is not available.
  - ❌ Does not guarantee ordering (jobs are independent).
  - ❌ Does not attempt to "exactly once" deliver; handlers must be idempotent.

  ## Important notes

  - You must provide a tenant schema (e.g. `"org_demo"`), because Signals are tenant-scoped.
  - Replay is intended for operational use, migrations, and debugging.
  """

  require Logger
  import Ash.Expr, only: [expr: 1]
  require Ash.Query

  alias FleetPrompt.Signals.Signal

  @type tenant :: binary()

  @doc """
  Re-enqueue fanout jobs for the most recent signals in `tenant`.

  Options:
  - `:limit` (default: 100, max: 5_000)
  - `:only_names` list of signal names to include
  - `:exclude_names` list of signal names to exclude

  Returns `{:ok, %{enqueued: n, skipped: n}}` or `{:error, reason}`.
  """
  @spec replay_recent(tenant(), keyword()) :: {:ok, map()} | {:error, term()}
  def replay_recent(tenant, opts \\ []) when is_binary(tenant) do
    limit = opts |> Keyword.get(:limit, 100) |> clamp_int(1, 5_000)
    only_names = normalize_string_list(Keyword.get(opts, :only_names))
    exclude_names = normalize_string_list(Keyword.get(opts, :exclude_names))

    query =
      Signal
      |> Ash.Query.for_read(:read)
      |> maybe_filter_names(only_names, exclude_names)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(limit)

    with {:ok, signals} <- Ash.read(query, tenant: tenant) do
      enqueue_fanout_for_signals(tenant, signals, opts)
    end
  end

  @doc """
  Re-enqueue fanout jobs for signals matching a single `name` in `tenant`.

  Options:
  - `:limit` (default: 500, max: 10_000)

  Returns `{:ok, %{enqueued: n, skipped: n}}` or `{:error, reason}`.
  """
  @spec replay_by_name(tenant(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def replay_by_name(tenant, name, opts \\ [])
      when is_binary(tenant) and is_binary(name) do
    limit = opts |> Keyword.get(:limit, 500) |> clamp_int(1, 10_000)
    name = String.trim(name)

    query =
      Signal
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(name == ^name))
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(limit)

    with {:ok, signals} <- Ash.read(query, tenant: tenant) do
      enqueue_fanout_for_signals(tenant, signals, opts)
    end
  end

  @doc """
  Re-enqueue fanout jobs for a specific list of `signal_ids` in `tenant`.

  Returns `{:ok, %{enqueued: n, skipped: n}}` or `{:error, reason}`.
  """
  @spec replay_by_ids(tenant(), [binary()], keyword()) :: {:ok, map()} | {:error, term()}
  def replay_by_ids(tenant, signal_ids, opts \\ [])
      when is_binary(tenant) and is_list(signal_ids) do
    ids =
      signal_ids
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if ids == [] do
      {:ok, %{enqueued: 0, skipped: 0}}
    else
      query =
        Signal
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(expr(id in ^ids))
        |> Ash.Query.limit(length(ids))

      with {:ok, signals} <- Ash.read(query, tenant: tenant) do
        enqueue_fanout_for_signals(tenant, signals, opts)
      end
    end
  end

  @doc """
  Re-enqueue fanout jobs for signals within an inserted_at time window.

  - `from_dt` and `to_dt` should be `DateTime` structs (UTC recommended).

  Options:
  - `:limit` (default: 5_000, max: 50_000)
  - `:only_names` list of signal names to include
  - `:exclude_names` list of signal names to exclude
  - `:order` `:asc` or `:desc` (default: `:asc`)

  Returns `{:ok, %{enqueued: n, skipped: n}}` or `{:error, reason}`.
  """
  @spec replay_time_range(tenant(), DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def replay_time_range(tenant, %DateTime{} = from_dt, %DateTime{} = to_dt, opts \\ [])
      when is_binary(tenant) do
    limit = opts |> Keyword.get(:limit, 5_000) |> clamp_int(1, 50_000)
    order = opts |> Keyword.get(:order, :asc) |> normalize_order()
    only_names = normalize_string_list(Keyword.get(opts, :only_names))
    exclude_names = normalize_string_list(Keyword.get(opts, :exclude_names))

    query =
      Signal
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(inserted_at >= ^from_dt and inserted_at <= ^to_dt))
      |> maybe_filter_names(only_names, exclude_names)
      |> Ash.Query.sort(inserted_at: order)
      |> Ash.Query.limit(limit)

    with {:ok, signals} <- Ash.read(query, tenant: tenant) do
      enqueue_fanout_for_signals(tenant, signals, opts)
    end
  end

  @doc """
  Enqueue a fanout job for a single signal id.

  Returns:
  - `{:ok, :enqueued}` when a job was inserted
  - `{:ok, :skipped}` if Oban/worker isn't available
  - `{:error, reason}` on insert failure
  """
  @spec enqueue_fanout(tenant(), binary(), keyword()) ::
          {:ok, :enqueued | :skipped} | {:error, term()}
  def enqueue_fanout(tenant, signal_id, opts \\ [])
      when is_binary(tenant) and is_binary(signal_id) do
    signal_id = String.trim(signal_id)

    cond do
      signal_id == "" ->
        {:error, "signal_id is required"}

      not Code.ensure_loaded?(Oban) ->
        {:ok, :skipped}

      not Code.ensure_loaded?(FleetPrompt.Jobs.SignalFanout) ->
        {:ok, :skipped}

      not function_exported?(FleetPrompt.Jobs.SignalFanout, :new, 1) ->
        {:ok, :skipped}

      true ->
        extra_args =
          opts
          |> Keyword.get(:fanout_args, %{})
          |> normalize_map()

        job =
          FleetPrompt.Jobs.SignalFanout.new(
            Map.merge(extra_args, %{
              "signal_id" => signal_id,
              "tenant" => tenant
            })
          )

        case Oban.insert(job) do
          {:ok, _job} -> {:ok, :enqueued}
          {:error, err} -> {:error, err}
        end
    end
  end

  # -----------------------
  # Internals
  # -----------------------

  defp enqueue_fanout_for_signals(tenant, signals, opts) when is_list(signals) do
    total = length(signals)

    if total == 0 do
      {:ok, %{enqueued: 0, skipped: 0}}
    else
      {enqueued, skipped} =
        Enum.reduce(signals, {0, 0}, fn signal, {enq, skp} ->
          case enqueue_fanout(tenant, signal.id, opts) do
            {:ok, :enqueued} ->
              {enq + 1, skp}

            {:ok, :skipped} ->
              {enq, skp + 1}

            {:error, err} ->
              Logger.warning("[Signals.Replay] failed to enqueue fanout job",
                tenant: tenant,
                signal_id: signal.id,
                signal_name: signal.name,
                error: normalize_error(err)
              )

              {enq, skp}
          end
        end)

      {:ok, %{enqueued: enqueued, skipped: skipped, total: total}}
    end
  end

  defp maybe_filter_names(query, [], []), do: query

  defp maybe_filter_names(query, only_names, exclude_names) do
    query
    |> case do
      q when is_list(only_names) and only_names != [] ->
        Ash.Query.filter(q, expr(name in ^only_names))

      q ->
        q
    end
    |> case do
      q when is_list(exclude_names) and exclude_names != [] ->
        Ash.Query.filter(q, expr(name not in ^exclude_names))

      q ->
        q
    end
  end

  defp normalize_string_list(nil), do: []

  defp normalize_string_list(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_string_list(other), do: normalize_string_list(List.wrap(other))

  defp normalize_order(:asc), do: :asc
  defp normalize_order(:desc), do: :desc
  defp normalize_order("asc"), do: :asc
  defp normalize_order("desc"), do: :desc
  defp normalize_order(_), do: :asc

  defp normalize_map(%{} = m), do: m
  defp normalize_map(nil), do: %{}
  defp normalize_map(_), do: %{}

  defp clamp_int(v, min, max) when is_integer(v), do: v |> max(min) |> min(max)

  defp clamp_int(v, min, max) do
    case Integer.parse(to_string(v)) do
      {i, _} -> clamp_int(i, min, max)
      :error -> min
    end
  end

  defp normalize_error(%{__exception__: true} = err), do: Exception.message(err)
  defp normalize_error(err) when is_binary(err), do: err
  defp normalize_error(err), do: inspect(err)
end
