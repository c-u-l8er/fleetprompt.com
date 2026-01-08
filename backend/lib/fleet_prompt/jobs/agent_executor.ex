defmodule FleetPrompt.Jobs.AgentExecutor do
  @moduledoc """
  Executes a persisted tenant-scoped `FleetPrompt.Agents.Execution` by calling the LLM facade.

  This job is the “Execution thin slice” runner:
  - Loads an `Execution` record (tenant-scoped).
  - Loads the referenced `Agent` (tenant-scoped).
  - Marks the execution `:running`.
  - Builds chat messages from:
    - agent `system_prompt`
    - optional `execution.request["messages"]` (OpenAI-style) or `execution.request["conversation_history"]`
    - the `execution.input` as the final user message
  - Calls `FleetPrompt.LLM.chat_completion/2`.
  - Marks execution `:succeeded` (with output + usage) or `:failed` (with sanitized error).
  - Writes durable `ExecutionLog` entries (best-effort) for operator visibility.
  - Emits best-effort Signals (if Signals is present) for auditability.

  ## Expected Oban args
  - `"tenant"`: required (e.g. `"org_demo"`)
  - `"execution_id"`: required (UUID)

  ## Idempotency
  - If the execution is already in a terminal state (`:succeeded`, `:failed`, `:canceled`), the job returns `:ok`.
  - If the job retries while the execution is `:running`, we will attempt to run again (best-effort).
    This is acceptable for early phases, but later hardening should introduce a stricter attempt/lock model.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias FleetPrompt.Agents.{Agent, Execution, ExecutionLog}
  alias FleetPrompt.LLM

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) when is_map(args) do
    with {:ok, tenant} <- fetch_required_string(args, "tenant"),
         {:ok, execution_id} <- fetch_required_string(args, "execution_id"),
         {:ok, %Execution{} = execution} <- load_execution(execution_id, tenant),
         {:ok, :continue} <- short_circuit_if_terminal(execution),
         {:ok, %Agent{} = agent} <- load_agent(execution.agent_id, tenant),
         {:ok, %Execution{} = execution} <- mark_running(execution, tenant, job),
         :ok <- log(execution, tenant, :info, "execution.started", %{"agent_id" => agent.id}),
         :ok <- emit_signal_started(execution, agent, tenant, job),
         {:ok, llm_result} <- call_llm(execution, agent),
         {:ok, %Execution{} = _execution} <- mark_succeeded(execution, tenant, llm_result),
         :ok <- log(execution, tenant, :info, "execution.succeeded", %{"usage" => llm_result.usage}),
         :ok <- emit_signal_succeeded(execution, agent, tenant, job, llm_result) do
      :ok
    else
      {:halt, :terminal} ->
        # terminal short-circuit
        :ok

      {:error, reason} ->
        tenant = Map.get(args, "tenant")
        execution_id = Map.get(args, "execution_id")

        Logger.warning("[AgentExecutor] execution failed",
          tenant: tenant,
          execution_id: execution_id,
          error: normalize_error(reason)
        )

        # Best-effort: attempt to mark failed if we can load the record.
        _ = maybe_mark_failed(tenant, execution_id, reason)

        # Best-effort: attempt to log + signal failure.
        _ = maybe_log_failed(tenant, execution_id, reason)
        _ = maybe_emit_signal_failed(tenant, execution_id, job, reason)

        {:error, normalize_error(reason)}
    end
  end

  def perform(%Oban.Job{} = job) do
    {:error, "expected job args to be an object, got: #{inspect(job.args)}"}
  end

  # -----------------------
  # Loaders
  # -----------------------

  defp load_execution(execution_id, tenant) when is_binary(execution_id) and is_binary(tenant) do
    case Ash.get(Execution, execution_id, tenant: tenant) do
      {:ok, %Execution{} = exec} -> {:ok, exec}
      {:ok, nil} -> {:error, "execution not found"}
      {:error, err} -> {:error, err}
    end
  end

  defp load_agent(agent_id, tenant) when is_binary(tenant) do
    case Ash.get(Agent, agent_id, tenant: tenant) do
      {:ok, %Agent{} = agent} -> {:ok, agent}
      {:ok, nil} -> {:error, "agent not found"}
      {:error, err} -> {:error, err}
    end
  end

  # -----------------------
  # State / lifecycle helpers
  # -----------------------

  defp short_circuit_if_terminal(%Execution{state: state}) when state in [:succeeded, :failed, :canceled] do
    {:halt, :terminal}
  end

  defp short_circuit_if_terminal(%Execution{}), do: {:ok, :continue}

  defp mark_running(%Execution{} = execution, tenant, %Oban.Job{} = job) do
    meta =
      execution.metadata
      |> ensure_map()
      |> Map.merge(%{
        "oban_job_id" => job.id,
        "oban_attempt" => job.attempt,
        "started_by" => "agent_executor"
      })

    execution
    |> Ash.Changeset.for_update(:mark_running, %{metadata: meta})
    |> Ash.update(tenant: tenant)
  end

  defp mark_succeeded(%Execution{} = execution, tenant, %{content: content, usage: usage} = _llm_result) do
    usage = ensure_map(usage)

    attrs = %{
      output: content,
      prompt_tokens: usage_int(usage, "prompt_tokens"),
      completion_tokens: usage_int(usage, "completion_tokens"),
      total_tokens: usage_int(usage, "total_tokens"),
      metadata: ensure_map(execution.metadata)
    }

    execution
    |> Ash.Changeset.for_update(:mark_succeeded, attrs)
    |> Ash.update(tenant: tenant)
  end

  defp mark_succeeded(%Execution{} = _execution, _tenant, _llm_result) do
    {:error, "LLM result missing expected fields (content/usage)"}
  end

  defp maybe_mark_failed(nil, _execution_id, _reason), do: :ok
  defp maybe_mark_failed("", _execution_id, _reason), do: :ok

  defp maybe_mark_failed(tenant, execution_id, reason) when is_binary(tenant) and is_binary(execution_id) do
    with {:ok, %Execution{} = execution} <- load_execution(execution_id, tenant) do
      # Only transition to failed if not already terminal.
      if execution.state in [:succeeded, :failed, :canceled] do
        :ok
      else
        msg = normalize_error(reason)

        execution
        |> Ash.Changeset.for_update(
          :mark_failed,
          %{
            error: truncate(msg, 1200),
            metadata: ensure_map(execution.metadata)
          }
        )
        |> Ash.update(tenant: tenant)
        |> case do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
      end
    else
      _ -> :ok
    end
  end

  # -----------------------
  # LLM call
  # -----------------------

  defp call_llm(%Execution{} = execution, %Agent{} = agent) do
    messages = build_messages(execution, agent)

    opts = [
      provider: :openrouter,
      model: resolve_model(execution, agent),
      max_tokens: resolve_max_tokens(execution, agent),
      temperature: resolve_temperature(execution, agent),
      timeout_ms: resolve_timeout_ms(agent),
      include_usage: true
    ]

    case LLM.chat_completion(messages, opts) do
      {:ok, %{content: content} = result} ->
        {:ok, %{
          content: content,
          usage: Map.get(result, :usage) || Map.get(result, "usage"),
          provider: Map.get(result, :provider) || :openrouter,
          model: Map.get(result, :model) || opts[:model]
        }}

      {:error, %LLM.Error{} = err} ->
        {:error, err}

      {:error, other} ->
        {:error, other}
    end
  end

  defp build_messages(%Execution{} = execution, %Agent{} = agent) do
    system = agent.system_prompt |> to_string() |> String.trim()

    base =
      if system == "" do
        []
      else
        [%{role: "system", content: system}]
      end

    extra =
      execution.request
      |> ensure_map()
      |> extract_history_messages()

    user_input =
      execution.input
      |> to_string()
      |> String.trim()

    base ++ extra ++ [%{role: "user", content: user_input}]
  end

  defp extract_history_messages(%{"messages" => msgs}) when is_list(msgs), do: sanitize_messages(msgs)
  defp extract_history_messages(%{"conversation_history" => msgs}) when is_list(msgs), do: sanitize_messages(msgs)
  defp extract_history_messages(%{}), do: []

  defp sanitize_messages(messages) when is_list(messages) do
    Enum.flat_map(messages, fn
      %{"role" => role, "content" => content} when is_binary(role) and is_binary(content) ->
        [%{role: role, content: content}]

      %{role: role, content: content} when is_binary(role) and is_binary(content) ->
        [%{role: role, content: content}]

      _ ->
        []
    end)
  end

  defp resolve_model(%Execution{} = execution, %Agent{} = agent) do
    # Priority:
    # 1) execution.model (if set)
    # 2) agent.config["model"]
    # 3) config default (runtime overrides in config/runtime.exs)
    exec_model = execution.model |> to_string() |> String.trim()

    model =
      cond do
        exec_model != "" -> exec_model
        is_map(agent.config) and is_binary(agent.config["model"]) and String.trim(agent.config["model"]) != "" -> agent.config["model"]
        true -> default_openrouter_model()
      end

    normalize_openrouter_model(model)
  end

  defp default_openrouter_model do
    llm = Application.get_env(:fleet_prompt, :llm, [])
    openrouter = Keyword.get(llm, :openrouter, [])
    Keyword.get(openrouter, :default_model, "openai/gpt-4o-mini")
  end

  defp normalize_openrouter_model(model) when is_binary(model) do
    m = String.trim(model)

    cond do
      m == "" ->
        default_openrouter_model()

      String.starts_with?(m, "openrouter/") ->
        String.replace_prefix(m, "openrouter/", "")

      true ->
        m
    end
  end

  defp resolve_max_tokens(%Execution{} = execution, %Agent{} = _agent) do
    cond do
      is_integer(execution.max_tokens) and execution.max_tokens > 0 -> execution.max_tokens
      true -> 1024
    end
  end

  defp resolve_temperature(%Execution{} = execution, %Agent{} = _agent) do
    cond do
      is_number(execution.temperature) -> execution.temperature
      true -> 0.7
    end
  end

  defp resolve_timeout_ms(%Agent{timeout_seconds: s}) when is_integer(s) and s > 0, do: s * 1_000
  defp resolve_timeout_ms(%Agent{}), do: 30_000

  # -----------------------
  # Durable logs (best-effort)
  # -----------------------

  defp log(%Execution{} = execution, tenant, level, message, data \\ %{})
       when is_binary(tenant) and is_atom(level) and is_binary(message) do
    attrs = %{
      execution_id: execution.id,
      level: level,
      message: message,
      data: ensure_map(data),
      occurred_at: DateTime.utc_now()
    }

    case Ash.create(ExecutionLog, attrs, tenant: tenant) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  rescue
    _ -> :ok
  end

  defp maybe_log_failed(nil, _execution_id, _reason), do: :ok
  defp maybe_log_failed("", _execution_id, _reason), do: :ok

  defp maybe_log_failed(tenant, execution_id, reason) do
    with {:ok, %Execution{} = exec} <- load_execution(execution_id, tenant) do
      _ = log(exec, tenant, :error, "execution.failed", %{"error" => normalize_error(reason)})
      :ok
    else
      _ -> :ok
    end
  end

  # -----------------------
  # Signals (best-effort; optional)
  # -----------------------

  defp emit_signal_started(%Execution{} = execution, %Agent{} = agent, tenant, %Oban.Job{} = job) do
    maybe_emit_signal(
      name: "agent.execution.started",
      tenant: tenant,
      payload: %{
        "execution_id" => execution.id,
        "agent_id" => agent.id,
        "model" => resolve_model(execution, agent),
        "input_preview" => truncate(to_string(execution.input || ""), 200)
      },
      metadata: %{
        "tenant" => tenant,
        "oban_job_id" => job.id,
        "subject" => %{"type" => "execution", "id" => execution.id}
      },
      dedupe_key: "agent.exec.started:#{tenant}:#{execution.id}"
    )
  end

  defp emit_signal_succeeded(%Execution{} = execution, %Agent{} = agent, tenant, %Oban.Job{} = job, llm_result) do
    maybe_emit_signal(
      name: "agent.execution.succeeded",
      tenant: tenant,
      payload: %{
        "execution_id" => execution.id,
        "agent_id" => agent.id,
        "model" => resolve_model(execution, agent),
        "usage" => ensure_map(llm_result.usage),
        "output_preview" => truncate(to_string(llm_result.content || ""), 200)
      },
      metadata: %{
        "tenant" => tenant,
        "oban_job_id" => job.id,
        "subject" => %{"type" => "execution", "id" => execution.id}
      },
      dedupe_key: "agent.exec.succeeded:#{tenant}:#{execution.id}"
    )
  end

  defp maybe_emit_signal_failed(tenant, execution_id, %Oban.Job{} = job, reason)
       when is_binary(tenant) and is_binary(execution_id) do
    maybe_emit_signal(
      name: "agent.execution.failed",
      tenant: tenant,
      payload: %{
        "execution_id" => execution_id,
        "error" => normalize_error(reason)
      },
      metadata: %{
        "tenant" => tenant,
        "oban_job_id" => job.id,
        "subject" => %{"type" => "execution", "id" => execution_id}
      },
      dedupe_key: "agent.exec.failed:#{tenant}:#{execution_id}"
    )
  end

  defp maybe_emit_signal_failed(_tenant, _execution_id, _job, _reason), do: :ok

  defp maybe_emit_signal(opts) do
    # Signals exist in this codebase; keep this best-effort and non-fatal.
    try do
      FleetPrompt.Signals.SignalBus.emit(opts)
      :ok
    rescue
      _ -> :ok
    end
  end

  # -----------------------
  # Small helpers
  # -----------------------

  defp fetch_required_string(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      v when is_binary(v) ->
        v = String.trim(v)
        if v == "", do: {:error, "missing required arg: #{key}"}, else: {:ok, v}

      _ ->
        {:error, "missing required arg: #{key}"}
    end
  end

  defp ensure_map(nil), do: %{}
  defp ensure_map(%{} = m), do: m
  defp ensure_map(other) when is_list(other), do: Map.new(other)
  defp ensure_map(_), do: %{}

  defp usage_int(%{} = usage, key) when is_binary(key) do
    case Map.get(usage, key) || Map.get(usage, String.to_atom(key)) do
      n when is_integer(n) and n >= 0 -> n
      n when is_number(n) and n >= 0 -> trunc(n)
      n when is_binary(n) -> parse_int(n) || 0
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp truncate(s, max) when is_binary(s) and is_integer(max) and max > 0 do
    if String.length(s) <= max do
      s
    else
      String.slice(s, 0, max) <> "…"
    end
  end

  defp normalize_error(%LLM.Error{} = err), do: err.message
  defp normalize_error(err) when is_binary(err), do: err
  defp normalize_error(%{message: msg}) when is_binary(msg), do: msg
  defp normalize_error(%{reason: reason}), do: normalize_error(reason)
  defp normalize_error(err), do: inspect(err)
end
