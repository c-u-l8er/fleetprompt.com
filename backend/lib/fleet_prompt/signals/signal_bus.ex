defmodule FleetPrompt.Signals.SignalBus do
  @moduledoc """
  SignalBus is the single entrypoint for emitting **Signals** (Phase 2B).

  Goals:
  - Provide a consistent API to emit tenant-scoped signals.
  - Support idempotency via `dedupe_key` (recommended).
  - Optionally enqueue fanout processing (durable handlers) when available.

  Notes:
  - Signals are immutable facts. This module only *creates* signals.
  - Do **not** store secrets in `payload` or `metadata`.
  """

  require Logger

  alias FleetPrompt.Signals.Signal

  @type tenant :: binary()
  @type signal_name :: binary()
  @type json_map :: map()

  @typedoc "Options controlling how a signal is emitted and processed."
  @type emit_opts :: [
          dedupe_key: binary() | nil,
          occurred_at: DateTime.t() | nil,
          correlation_id: binary() | nil,
          causation_id: binary() | nil,
          actor: %{type: binary() | nil, id: binary() | nil} | nil,
          subject: %{type: binary() | nil, id: binary() | nil} | nil,
          source: binary() | nil,
          enqueue_fanout?: boolean(),
          fanout_args: map()
        ]

  @default_enqueue_fanout? true

  @doc """
  Emit a signal for a given `tenant`.

  Returns:
  - `{:ok, %Signal{}, :created}` when a new signal row is persisted
  - `{:ok, %Signal{}, :existing}` when the signal already exists (dedupe hit)
  - `{:error, term()}` for other failures

  Idempotency:
  - If `dedupe_key` is present, we will try to return an existing signal before/after
    attempting a create.
  - If `dedupe_key` is absent, every call will create a new signal (append-only).

  Fanout:
  - If `enqueue_fanout?: true` and a `FleetPrompt.Jobs.SignalFanout` worker exists,
    this will enqueue a job to process handlers for the signal.
  """
  @spec emit(tenant(), signal_name(), json_map(), emit_opts()) ::
          {:ok, Signal.t(), :created | :existing} | {:error, term()}
  def emit(tenant, name, payload, opts \\ [])
      when is_binary(tenant) and is_binary(name) and is_map(payload) do
    metadata = Keyword.get(opts, :metadata, %{})
    opts = Keyword.delete(opts, :metadata)

    do_emit(tenant, name, payload, metadata, opts)
  end

  @doc """
  Same as `emit/4`, but raises on error and returns the signal.

  The return value is always `%Signal{}`; the `:created | :existing` marker is
  discarded. Use `emit/4` if you need that information.
  """
  @spec emit!(tenant(), signal_name(), json_map(), emit_opts()) :: Signal.t()
  def emit!(tenant, name, payload, opts \\ []) do
    case emit(tenant, name, payload, opts) do
      {:ok, %Signal{} = signal, _marker} ->
        signal

      {:error, err} ->
        raise(RuntimeError, "failed to emit signal #{inspect(name)}: #{inspect(err)}")
    end
  end

  @doc """
  Convenience wrapper that allows passing `metadata` explicitly.

  This exists mainly to keep callsites readable:

      SignalBus.emit(tenant, "package.install.requested", payload, metadata, dedupe_key: "...")

  """
  @spec emit(tenant(), signal_name(), json_map(), json_map(), emit_opts()) ::
          {:ok, Signal.t(), :created | :existing} | {:error, term()}
  def emit(tenant, name, payload, metadata, opts)
      when is_binary(tenant) and is_binary(name) and is_map(payload) and is_map(metadata) do
    do_emit(tenant, name, payload, metadata, opts)
  end

  # -------------------------
  # Internal implementation
  # -------------------------

  defp do_emit(tenant, name, payload, metadata, opts) do
    dedupe_key = opts |> Keyword.get(:dedupe_key) |> normalize_optional_string()
    enqueue_fanout? = Keyword.get(opts, :enqueue_fanout?, @default_enqueue_fanout?)

    # Fast path: if we have a dedupe key and the signal already exists, return it.
    if is_binary(dedupe_key) do
      case get_by_dedupe_key(tenant, dedupe_key) do
        {:ok, %Signal{} = existing} ->
          maybe_enqueue_fanout(existing, tenant, enqueue_fanout?, opts)
          {:ok, existing, :existing}

        {:ok, nil} ->
          create_or_get_existing(
            tenant,
            name,
            payload,
            metadata,
            dedupe_key,
            enqueue_fanout?,
            opts
          )

        {:error, err} ->
          {:error, err}
      end
    else
      create_signal(tenant, name, payload, metadata, nil, enqueue_fanout?, opts)
    end
  end

  defp create_or_get_existing(tenant, name, payload, metadata, dedupe_key, enqueue_fanout?, opts) do
    case create_signal(tenant, name, payload, metadata, dedupe_key, enqueue_fanout?, opts) do
      {:ok, %Signal{} = created, :created} ->
        {:ok, created, :created}

      {:error, err} ->
        # If the create failed due to a uniqueness race on dedupe_key, re-read and return existing.
        if looks_like_dedupe_conflict?(err) do
          case get_by_dedupe_key(tenant, dedupe_key) do
            {:ok, %Signal{} = existing} ->
              maybe_enqueue_fanout(existing, tenant, enqueue_fanout?, opts)
              {:ok, existing, :existing}

            {:ok, nil} ->
              {:error, err}

            {:error, read_err} ->
              {:error, read_err}
          end
        else
          {:error, err}
        end
    end
  end

  defp create_signal(tenant, name, payload, metadata, dedupe_key, enqueue_fanout?, opts) do
    actor = Keyword.get(opts, :actor)
    subject = Keyword.get(opts, :subject)

    attrs =
      %{
        name: String.trim(name),
        dedupe_key: dedupe_key,
        payload: payload || %{},
        metadata: metadata || %{},
        occurred_at: Keyword.get(opts, :occurred_at),
        correlation_id: Keyword.get(opts, :correlation_id) |> normalize_optional_string(),
        causation_id: Keyword.get(opts, :causation_id) |> normalize_optional_string(),
        actor_type: actor_type(actor),
        actor_id: actor_id(actor),
        subject_type: subject_type(subject),
        subject_id: subject_id(subject),
        source: Keyword.get(opts, :source) |> normalize_optional_string()
      }
      |> drop_nils()

    changeset =
      Signal
      |> Ash.Changeset.for_create(:emit, attrs)
      |> Ash.Changeset.set_tenant(tenant)

    case Ash.create(changeset) do
      {:ok, %Signal{} = signal} ->
        maybe_enqueue_fanout(signal, tenant, enqueue_fanout?, opts)
        {:ok, signal, :created}

      {:error, err} ->
        {:error, err}
    end
  end

  defp get_by_dedupe_key(tenant, dedupe_key) when is_binary(tenant) and is_binary(dedupe_key) do
    query =
      Signal
      |> Ash.Query.for_read(:by_dedupe_key, %{dedupe_key: dedupe_key})

    Ash.read_one(query, tenant: tenant)
  end

  defp maybe_enqueue_fanout(%Signal{} = signal, tenant, true, opts) do
    # Fanout is optional: only enqueue if the worker exists at runtime.
    # This avoids boot/compile failures while Phase 2B is being implemented incrementally.
    fanout_args = Keyword.get(opts, :fanout_args, %{}) || %{}

    cond do
      not Code.ensure_loaded?(Oban) ->
        :ok

      not Code.ensure_loaded?(FleetPrompt.Jobs.SignalFanout) ->
        :ok

      not function_exported?(FleetPrompt.Jobs.SignalFanout, :new, 1) ->
        :ok

      true ->
        job =
          FleetPrompt.Jobs.SignalFanout.new(
            Map.merge(fanout_args, %{
              "signal_id" => signal.id,
              "tenant" => tenant
            })
          )

        case Oban.insert(job) do
          {:ok, _job} ->
            :ok

          {:error, err} ->
            Logger.warning("[SignalBus] failed to enqueue signal fanout job",
              tenant: tenant,
              signal_id: signal.id,
              signal_name: signal.name,
              error: inspect(err)
            )

            :ok
        end
    end
  end

  defp maybe_enqueue_fanout(_signal, _tenant, _enqueue?, _opts), do: :ok

  defp looks_like_dedupe_conflict?(%{__exception__: true} = err) do
    msg = Exception.message(err)

    # Best-effort detection; exact error types differ across AshPostgres/Ash versions.
    String.contains?(msg, "unique_dedupe_key") or
      (String.contains?(msg, "dedupe_key") and
         (String.contains?(msg, "unique") or String.contains?(msg, "duplicate") or
            String.contains?(msg, "already exists")))
  end

  defp looks_like_dedupe_conflict?(err) when is_binary(err) do
    looks_like_dedupe_conflict?(%RuntimeError{message: err})
  end

  defp looks_like_dedupe_conflict?(_), do: false

  defp actor_type(%{type: t}) when is_binary(t), do: normalize_optional_string(t)
  defp actor_type(%{"type" => t}) when is_binary(t), do: normalize_optional_string(t)
  defp actor_type(_), do: nil

  defp actor_id(%{id: id}) when is_binary(id), do: normalize_optional_string(id)
  defp actor_id(%{"id" => id}) when is_binary(id), do: normalize_optional_string(id)
  defp actor_id(_), do: nil

  defp subject_type(%{type: t}) when is_binary(t), do: normalize_optional_string(t)
  defp subject_type(%{"type" => t}) when is_binary(t), do: normalize_optional_string(t)
  defp subject_type(_), do: nil

  defp subject_id(%{id: id}) when is_binary(id), do: normalize_optional_string(id)
  defp subject_id(%{"id" => id}) when is_binary(id), do: normalize_optional_string(id)
  defp subject_id(_), do: nil

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      s -> s
    end
  end

  defp normalize_optional_string(v), do: v |> to_string() |> normalize_optional_string()

  defp drop_nils(map) when is_map(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) end)
  end
end
