defmodule FleetPromptWeb.ExecutionController do
  @moduledoc """
  JSON endpoints to create and poll tenant-scoped agent executions.

  This controller is intended as a thin transport layer over:
  - `FleetPrompt.Agents.Execution` (tenant-scoped, persisted)
  - `FleetPrompt.Agents.ExecutionLog` (tenant-scoped, persisted)
  - `FleetPrompt.Jobs.AgentExecutor` (Oban job runner)

  Expected usage:
  - `POST /executions` to create an execution and enqueue the runner job
  - `GET /executions/:id/status` to poll state/output/error
  - `GET /executions/:id` to fetch full detail including logs (optional but handy)
  """

  use FleetPromptWeb, :controller

  require Logger

  alias FleetPrompt.Agents.{Execution, ExecutionLog}
  alias FleetPrompt.Jobs.AgentExecutor

  # -----------------------
  # Create
  # -----------------------

  # POST /executions
  #
  # JSON body:
  # {
  #   "agent_id": "...",
  #   "input": "Hello",
  #   "request": { ... }               (optional; may include "messages" or "conversation_history")
  #   "model": "anthropic/claude-3.5-sonnet" (optional)
  #   "max_tokens": 1024              (optional)
  #   "temperature": 0.7              (optional)
  # }
  #
  # Response (201):
  # {
  #   "execution": { ... },
  #   "job": { "id": 123 } | null
  # }
  def create(conn, params) when is_map(params) do
    with {:ok, tenant} <- fetch_tenant(conn),
         {:ok, agent_id} <- fetch_required_string(params, "agent_id"),
         {:ok, input} <- fetch_required_string(params, "input"),
         attrs <- build_execution_attrs(conn, params, agent_id, input),
         {:ok, %Execution{} = execution} <- create_execution(tenant, attrs) do
      case enqueue_execution_job(tenant, execution.id) do
        {:ok, job} ->
          conn
          |> put_status(:created)
          |> json(%{
            execution: serialize_execution(execution),
            job: %{id: job.id}
          })

        {:error, err} ->
          # Execution has been created, but runner job enqueue failed.
          # Keep this non-fatal so clients can still poll and operators can retry manually.
          Logger.warning("[ExecutionController] failed to enqueue AgentExecutor job",
            execution_id: execution.id,
            error: Exception.message(err)
          )

          conn
          |> put_status(:created)
          |> json(%{
            execution: serialize_execution(execution),
            job: nil,
            warning: "execution created but runner job enqueue failed"
          })
      end
    else
      {:error, :no_tenant} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no tenant context; ensure you are authenticated and have selected an organization"})

      {:error, {:missing_param, key}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "missing required parameter: #{key}"})

      {:error, err} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "failed to create execution", details: safe_ash_error(err)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "expected JSON body"})
  end

  # -----------------------
  # Poll / read
  # -----------------------

  # GET /executions/:id/status
  #
  # Minimal polling endpoint (fast):
  # {
  #   "execution": {
  #     "id": "...",
  #     "state": "queued|running|succeeded|failed|canceled",
  #     "output": "...",
  #     "error": "...",
  #     "updated_at": "...",
  #     "inserted_at": "..."
  #   }
  # }
  def status(conn, %{"id" => id}) when is_binary(id) do
    with {:ok, tenant} <- fetch_tenant(conn),
         {:ok, %Execution{} = execution} <- get_execution(tenant, id) do
      conn
      |> put_status(:ok)
      |> json(%{
        execution: serialize_execution_poll(execution)
      })
    else
      {:error, :no_tenant} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no tenant context"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "execution not found"})

      {:error, err} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: normalize_error(err)})
    end
  end

  def status(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "expected route param `id`"})
  end

  # GET /executions/:id
  #
  # Full detail endpoint (useful for UI/operator console):
  # - includes logs
  def show(conn, %{"id" => id}) when is_binary(id) do
    with {:ok, tenant} <- fetch_tenant(conn),
         {:ok, %Execution{} = execution} <- get_execution(tenant, id),
         {:ok, logs} <- get_execution_logs(tenant, id) do
      conn
      |> put_status(:ok)
      |> json(%{
        execution: serialize_execution(execution),
        logs: Enum.map(logs, &serialize_log/1)
      })
    else
      {:error, :no_tenant} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no tenant context"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "execution not found"})

      {:error, err} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: normalize_error(err)})
    end
  end

  def show(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "expected route param `id`"})
  end

  # -----------------------
  # Internal helpers
  # -----------------------

  defp fetch_tenant(conn) do
    case conn.assigns[:ash_tenant] do
      tenant when is_binary(tenant) and tenant != "" -> {:ok, tenant}
      _ -> {:error, :no_tenant}
    end
  end

  defp build_execution_attrs(conn, params, agent_id, input) do
    request =
      case Map.get(params, "request") do
        %{} = m -> m
        _ -> %{}
      end

    model =
      case Map.get(params, "model") do
        m when is_binary(m) ->
          m = String.trim(m)
          if m != "", do: m, else: nil

        _ ->
          nil
      end

    max_tokens =
      case Map.get(params, "max_tokens") do
        n when is_integer(n) -> n
        n when is_binary(n) -> parse_int(n)
        _ -> nil
      end

    temperature =
      case Map.get(params, "temperature") do
        n when is_number(n) -> n
        n when is_binary(n) -> parse_float(n)
        _ -> nil
      end

    metadata =
      %{}
      |> maybe_put("request_id", request_id(conn))
      |> maybe_put("user_id", current_user_id(conn))
      |> maybe_put("source", "http")

    %{}
    |> Map.put(:agent_id, agent_id)
    |> Map.put(:input, input)
    |> Map.put(:request, request)
    |> Map.put(:metadata, metadata)
    |> maybe_put_attr(:model, model)
    |> maybe_put_attr(:max_tokens, max_tokens)
    |> maybe_put_attr(:temperature, temperature)
  end

  defp create_execution(tenant, attrs) do
    Execution
    |> Ash.Changeset.for_create(:request, attrs)
    |> Ash.Changeset.force_change_attribute(:output, "")
    |> Ash.create(tenant: tenant)
  end

  defp enqueue_execution_job(tenant, execution_id) do
    job =
      %{
        "tenant" => tenant,
        "execution_id" => execution_id
      }
      |> AgentExecutor.new()

    case Oban.insert(job) do
      {:ok, job} -> {:ok, job}
      {:error, err} -> {:error, err}
    end
  end

  defp get_execution(tenant, id) do
    case Ash.get(Execution, id, tenant: tenant) do
      {:ok, %Execution{} = exec} -> {:ok, exec}
      {:ok, nil} -> {:error, :not_found}
      {:error, err} -> {:error, err}
    end
  end

  defp get_execution_logs(tenant, execution_id) do
    Ash.read(ExecutionLog, :by_execution, %{execution_id: execution_id}, tenant: tenant)
  end

  defp serialize_execution(%Execution{} = e) do
    %{
      id: e.id,
      agent_id: e.agent_id,
      state: to_string(e.state),
      model: e.model,
      temperature: e.temperature,
      max_tokens: e.max_tokens,
      input: e.input,
      request: e.request || %{},
      output: e.output || "",
      error: e.error,
      prompt_tokens: e.prompt_tokens,
      completion_tokens: e.completion_tokens,
      total_tokens: e.total_tokens,
      cost_cents: e.cost_cents,
      started_at: iso(e.started_at),
      finished_at: iso(e.finished_at),
      metadata: e.metadata || %{},
      inserted_at: iso(e.inserted_at),
      updated_at: iso(e.updated_at)
    }
  end

  defp serialize_execution_poll(%Execution{} = e) do
    %{
      id: e.id,
      state: to_string(e.state),
      output: e.output || "",
      error: e.error,
      inserted_at: iso(e.inserted_at),
      updated_at: iso(e.updated_at)
    }
  end

  defp serialize_log(log) when is_map(log) do
    %{
      id: Map.get(log, :id) || Map.get(log, "id"),
      execution_id: Map.get(log, :execution_id) || Map.get(log, "execution_id"),
      level: to_string(Map.get(log, :level) || Map.get(log, "level") || "info"),
      message: Map.get(log, :message) || Map.get(log, "message"),
      data: Map.get(log, :data) || Map.get(log, "data") || %{},
      occurred_at: iso(Map.get(log, :occurred_at) || Map.get(log, "occurred_at")),
      inserted_at: iso(Map.get(log, :inserted_at) || Map.get(log, "inserted_at"))
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = ndt), do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  defp iso(_), do: nil

  defp fetch_required_string(params, key) when is_map(params) and is_binary(key) do
    case Map.get(params, key) do
      v when is_binary(v) ->
        v = String.trim(v)
        if v == "", do: {:error, {:missing_param, key}}, else: {:ok, v}

      _ ->
        {:error, {:missing_param, key}}
    end
  end

  defp request_id(conn) do
    conn.assigns[:request_id] ||
      List.first(get_req_header(conn, "x-request-id")) ||
      nil
  end

  defp current_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil) when is_map(map), do: map
  defp maybe_put(map, _key, "") when is_map(map), do: map

  defp maybe_put(map, key, val) when is_map(map) and is_binary(key) do
    Map.put(map, key, val)
  end

  defp maybe_put_attr(map, _key, nil) when is_map(map), do: map

  defp maybe_put_attr(map, key, val) when is_map(map) do
    Map.put(map, key, val)
  end

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_float(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp safe_ash_error(err) do
    # Keep it simple and avoid leaking large internals. This can be improved later.
    message =
      if Kernel.is_exception(err) do
        Exception.message(err)
      else
        inspect(err)
      end

    class =
      case err do
        %{__struct__: mod} when is_atom(mod) ->
          mod |> Module.split() |> List.last()

        _ ->
          nil
      end

    %{
      message: message,
      class: class
    }
  end

  defp normalize_error(%{message: msg}) when is_binary(msg), do: msg
  defp normalize_error(msg) when is_binary(msg), do: msg
  defp normalize_error(other), do: inspect(other)
end
