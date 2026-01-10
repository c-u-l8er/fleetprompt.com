defmodule FleetPromptWeb.ChatController do
  @moduledoc """
  Chat controller with an SSE streaming endpoint.

  - `index/2` renders the Inertia `Chat` page with a minimal starter payload.
  - `send_message/2` streams a response over Server-Sent Events (SSE).

  Execution model (current thin slice):
  - Uses `FleetPrompt.LLM` to stream a chat completion via OpenRouter (OpenAI-compatible SSE).
  - If the LLM is not configured (missing API key) or errors, falls back to a demo SSE response
    so the UI still proves end-to-end streaming mechanics.

  Notes:
  - This controller does *not* persist conversations/messages yet.
  - The SSE payload format is designed to be easy for the Svelte client to parse:
    each event is a JSON object sent as an SSE `data:` line.
  """

  use FleetPromptWeb, :controller

  require Logger
  require Ash.Query

  alias FleetPrompt.LLM
  alias FleetPrompt.Agents.Agent

  @sse_content_type "text/event-stream"

  # GET /chat
  #
  # You may currently be routing `/chat` to `PageController.chat/2`.
  # Once you switch the route to this controller, the UI can receive starter props.
  def index(conn, _params) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    agents = load_agents_for_chat(conn)
    default_agent_id = default_agent_id_from_agents(agents)

    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Chat", %{
      agents: agents,
      default_agent_id: default_agent_id,
      initialMessages: [
        %{
          id: "msg_welcome",
          role: "assistant",
          content:
            "Welcome to FleetPrompt Chat. Select an agent and send a message. (Streaming is backed by OpenRouter when configured.)",
          actions: [],
          inserted_at: now
        }
      ]
    })
  end

  # POST /chat/message
  #
  # Expects JSON body like: { "message": "hello", "agent_id": "..." }
  #
  # Responds with SSE:
  #   data: {"type":"chunk","chunk":"..."}
  #   data: {"type":"complete","message":{...}}
  def send_message(conn, %{"message" => content} = params) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "message cannot be empty"})
    else
      agent_id = Map.get(params, "agent_id")

      conn
      |> prepare_sse()
      |> stream_llm_response(content, agent_id)
    end
  end

  def send_message(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "expected JSON body with a string field `message`"})
  end

  defp prepare_sse(conn) do
    conn
    |> put_resp_content_type(@sse_content_type)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
  end

  # Stream a real LLM response (OpenRouter via FleetPrompt.LLM) if configured.
  # If it fails (e.g. missing API key), fall back to a demo stream so the UI still works.
  #
  # Tool calling:
  # - We pass `FleetPrompt.AI.Tools.definitions/0` as OpenAI-style tools.
  # - We run a small "tool loop": assistant -> tool(s) -> assistant.
  # - All output is streamed to the client as a single assistant response.
  defp stream_llm_response(conn, user_message, agent_id) do
    started_at = DateTime.utc_now()
    now_iso = DateTime.to_iso8601(started_at)

    Process.put(:fp_sse_conn, conn)
    Process.put(:fp_chat_started_at, now_iso)

    _ = sse_send_pd(%{type: "start", at: now_iso})

    # "Global" assistant text we stream to the client.
    Process.put(:fp_llm_acc, "")

    tenant = conn.assigns[:ash_tenant]
    actor_user_id = conn.assigns[:current_user] && conn.assigns.current_user.id

    system = build_system_prompt(tenant, actor_user_id, agent_id)

    base_messages = [
      %{role: "system", content: system},
      %{role: "user", content: user_message}
    ]

    tools = FleetPrompt.AI.Tools.definitions()

    opts = [
      provider: :openrouter,
      model: llm_default_model(),
      max_tokens: 800,
      temperature: 0.3,
      timeout_ms: 30_000,
      include_usage: true,
      tools: tools,
      tool_choice: "auto"
    ]

    case run_tool_loop(base_messages, tenant, actor_user_id, opts, max_rounds: 3) do
      {:ok, _final_meta} ->
        Process.get(:fp_sse_conn, conn)

      {:error, err} ->
        Logger.warning("[Chat] LLM/tool loop failed; falling back to demo SSE",
          error: normalize_error(err)
        )

        stream_demo_response(Process.get(:fp_sse_conn, conn), user_message, err)
    end
  end

  defp build_system_prompt(tenant, actor_user_id, agent_id) do
    tenant_line = if is_binary(tenant) and tenant != "", do: "Tenant: #{tenant}", else: "Tenant: (none)"

    actor_line =
      if is_binary(actor_user_id) and actor_user_id != "" do
        "Current user id: #{actor_user_id}"
      else
        "Current user id: (unknown)"
      end

    agent_line =
      if is_binary(agent_id) and String.trim(agent_id) != "" do
        "Selected agent id (UI hint only): #{String.trim(agent_id)}"
      else
        "Selected agent id: (none)"
      end

    """
    You are FleetPrompt’s assistant.

    #{tenant_line}
    #{actor_line}
    #{agent_line}

    Behavioral rules:
    - Be concise and helpful.
    - Do not claim you performed actions you did not perform.
    - If you need to use tools, call them instead of guessing.
    - Only call write tools (create_*) when the user explicitly asks to create something.

    Available tools are provided via the OpenAI tools interface.
    """
  end

  defp run_tool_loop(messages, tenant, actor_user_id, llm_opts, opts) when is_list(messages) do
    max_rounds = Keyword.get(opts, :max_rounds, 3)

    do_run_tool_loop(messages, tenant, actor_user_id, llm_opts, 1, max_rounds)
  end

  defp do_run_tool_loop(messages, tenant, actor_user_id, llm_opts, round, max_rounds)
       when round <= max_rounds do
    # Per-round assistant text (for history); global text is `:fp_llm_acc`.
    Process.put(:fp_llm_round_acc, "")
    Process.put(:fp_llm_tool_calls_acc, %{})
    Process.put(:fp_llm_last_meta, %{})

    on_event = fn
      {:chunk, chunk} when is_binary(chunk) and chunk != "" ->
        round_acc = Process.get(:fp_llm_round_acc, "")
        Process.put(:fp_llm_round_acc, round_acc <> chunk)

        acc = Process.get(:fp_llm_acc, "")
        Process.put(:fp_llm_acc, acc <> chunk)

        _ = sse_send_pd(%{type: "chunk", chunk: chunk})
        :ok

      {:tool_calls, tool_calls_delta} when is_list(tool_calls_delta) ->
        current = Process.get(:fp_llm_tool_calls_acc, %{})
        updated = merge_tool_call_deltas(current, tool_calls_delta)
        Process.put(:fp_llm_tool_calls_acc, updated)

        # Debug-only event; client ignores unknown types.
        _ = sse_send_pd(%{type: "tool_calls", count: map_size(updated)})
        :ok

      {:complete, meta} when is_map(meta) ->
        Process.put(:fp_llm_last_meta, meta)
        :ok

      _ ->
        :ok
    end

    case LLM.stream_chat_completion(messages, on_event, llm_opts) do
      {:ok, _info} ->
        meta = Process.get(:fp_llm_last_meta, %{})

        tool_calls =
          Process.get(:fp_llm_tool_calls_acc, %{})
          |> finalize_tool_calls()

        # Record the assistant turn (including tool_calls if present), then either finish or execute tools.
        assistant_turn =
          %{
            role: "assistant",
            content: Process.get(:fp_llm_round_acc, "")
          }
          |> maybe_put_tool_calls(tool_calls)

        messages = messages ++ [assistant_turn]

        if tool_calls == [] do
          finished_at = DateTime.utc_now()

          final_message = %{
            id: "assistant_" <> unique_suffix(),
            role: "assistant",
            content: Process.get(:fp_llm_acc, ""),
            actions: [],
            inserted_at: DateTime.to_iso8601(finished_at)
          }

          started_at_iso = Process.get(:fp_chat_started_at)

          _ =
            sse_send_pd(%{
              type: "complete",
              message: final_message,
              meta:
                Map.merge(
                  %{
                    started_at: started_at_iso,
                    finished_at: DateTime.to_iso8601(finished_at)
                  },
                  sanitize_llm_meta(meta)
                )
            })

          {:ok, meta}
        else
          tool_messages = execute_tool_calls(tool_calls, tenant, actor_user_id)

          # Continue the loop with appended tool results.
          do_run_tool_loop(messages ++ tool_messages, tenant, actor_user_id, llm_opts, round + 1, max_rounds)
        end

      {:error, err} ->
        {:error, err}
    end
  end

  defp do_run_tool_loop(_messages, _tenant, _actor_user_id, _llm_opts, _round, _max_rounds) do
    {:error, "tool loop exceeded max rounds"}
  end

  defp maybe_put_tool_calls(msg, []), do: msg
  defp maybe_put_tool_calls(msg, tool_calls) when is_list(tool_calls), do: Map.put(msg, :tool_calls, tool_calls)

  defp merge_tool_call_deltas(acc, deltas) when is_map(acc) and is_list(deltas) do
    Enum.reduce(deltas, acc, fn delta, a ->
      # Expected shape (OpenAI): %{"index" => 0, "id" => "...", "type" => "function", "function" => %{...}}
      idx = Map.get(delta, "index") || Map.get(delta, :index) || 0
      id = Map.get(delta, "id") || Map.get(delta, :id)
      type = Map.get(delta, "type") || Map.get(delta, :type) || "function"

      fun = Map.get(delta, "function") || Map.get(delta, :function) || %{}
      name = Map.get(fun, "name") || Map.get(fun, :name)
      args = Map.get(fun, "arguments") || Map.get(fun, :arguments)

      existing =
        Map.get(a, idx, %{
          "id" => id,
          "type" => type,
          "function" => %{"name" => name, "arguments" => ""}
        })

      existing_fun = Map.get(existing, "function", %{})
      existing_args = Map.get(existing_fun, "arguments", "")

      updated_fun =
        existing_fun
        |> maybe_put_if_present("name", name)
        |> Map.put("arguments", existing_args <> to_string(args || ""))

      updated =
        existing
        |> maybe_put_if_present("id", id)
        |> maybe_put_if_present("type", type)
        |> Map.put("function", updated_fun)

      Map.put(a, idx, updated)
    end)
  end

  defp maybe_put_if_present(map, _key, nil), do: map
  defp maybe_put_if_present(map, key, ""), do: map
  defp maybe_put_if_present(map, key, v), do: Map.put(map, key, v)

  defp finalize_tool_calls(acc) when is_map(acc) do
    acc
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map(fn {_idx, call} ->
      call = Map.put_new(call, "id", "call_" <> unique_suffix())

      fun = Map.get(call, "function", %{})
      args = Map.get(fun, "arguments") || "{}"
      fun = Map.put(fun, "arguments", if(String.trim(args) == "", do: "{}", else: args))

      Map.put(call, "function", fun)
    end)
  end

  defp execute_tool_calls(tool_calls, tenant, actor_user_id) do
    ctx = %{actor_user_id: actor_user_id}

    Enum.map(tool_calls, fn call ->
      tool_call_id = Map.get(call, "id") || "call_" <> unique_suffix()
      fun = Map.get(call, "function", %{})
      name = Map.get(fun, "name") || ""
      args_json = Map.get(fun, "arguments") || "{}"

      _ = sse_send_pd(%{type: "tool_start", tool: name})

      result =
        cond do
          !is_binary(tenant) or tenant == "" ->
            "Tool #{name} failed: missing tenant context"

          true ->
            with {:ok, args} <- safe_decode_args(args_json),
                 {:ok, output} <- FleetPrompt.AI.Tools.execute(name, args, tenant, ctx) do
              output
            else
              {:error, err} -> "Tool #{name} failed: #{normalize_error(err)}"
              other -> "Tool #{name} failed: #{inspect(other)}"
            end
        end

      _ = sse_send_pd(%{type: "tool_result", tool: name})

      %{
        role: "tool",
        tool_call_id: tool_call_id,
        content: result
      }
    end)
  end

  defp safe_decode_args(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, other} -> {:ok, %{"value" => other}}
      {:error, err} -> {:error, err}
    end
  end

  # Demo fallback stream (keeps the UI usable even when LLM config is missing).
  defp stream_demo_response(conn, user_message, reason) do
    started_at = DateTime.utc_now()

    Logger.debug("[Chat] streaming demo response", user_message: user_message)

    conn =
      case sse_send(conn, %{type: "start", at: DateTime.to_iso8601(started_at)}) do
        {:ok, conn} -> conn
        {:error, conn} -> conn
      end

    reason_text =
      case reason do
        nil -> ""
        _ -> "\n\n(LLM unavailable: #{normalize_error(reason)})"
      end

    # Stream a few chunks to prove incremental rendering works.
    chunks = [
      "Got it. You said: ",
      user_message,
      "\n\nThis endpoint can stream real LLM output when OpenRouter is configured." <> reason_text <>
        "\n\nTo enable: set OPENROUTER_API_KEY and retry."
    ]

    conn =
      Enum.reduce_while(chunks, conn, fn chunk, acc ->
        case sse_send(acc, %{type: "chunk", chunk: chunk}) do
          {:ok, acc} -> {:cont, acc}
          {:error, acc} -> {:halt, acc}
        end
      end)

    finished_at = DateTime.utc_now()

    final_message = %{
      id: "assistant_" <> unique_suffix(),
      role: "assistant",
      content: Enum.join(chunks, ""),
      actions: [],
      inserted_at: DateTime.to_iso8601(finished_at)
    }

    _ =
      case sse_send(conn, %{
             type: "complete",
             message: final_message,
             meta: %{
               started_at: DateTime.to_iso8601(started_at),
               finished_at: DateTime.to_iso8601(finished_at)
             }
           }) do
        {:ok, conn} -> conn
        {:error, conn} -> conn
      end

    # End the response cleanly (SSE streams can also be kept open; for now we finish per request).
    conn
  end

  defp load_agents_for_chat(conn) do
    tenant = conn.assigns[:ash_tenant]

    if is_binary(tenant) and tenant != "" do
      query = Agent |> Ash.Query.for_read(:read)

      case Ash.read(query, tenant: tenant) do
        {:ok, agents} ->
          Enum.map(agents, &serialize_agent_for_chat/1)

        {:error, _err} ->
          []
      end
    else
      []
    end
  rescue
    _ -> []
  end

  defp serialize_agent_for_chat(%Agent{} = agent) do
    config = agent.config || %{}

    %{
      id: agent.id,
      name: agent.name,
      description: agent.description,
      state: to_string(agent.state),
      model: Map.get(config, "model")
    }
  end

  defp default_agent_id_from_agents([%{id: id} | _]) when is_binary(id), do: id
  defp default_agent_id_from_agents(_), do: nil

  defp llm_default_model do
    llm = Application.get_env(:fleet_prompt, :llm, [])
    openrouter = Keyword.get(llm, :openrouter, [])
    Keyword.get(openrouter, :default_model, "openai/gpt-4o-mini")
  end

  defp sanitize_llm_meta(meta) when is_map(meta) do
    # Keep meta JSON-safe and small; avoid leaking any sensitive details.
    Map.take(meta, [:provider, :model, :usage])
  end

  defp sanitize_llm_meta(_), do: %{}

  defp sse_send_pd(data) when is_map(data) do
    conn = Process.get(:fp_sse_conn)

    case conn do
      %Plug.Conn{} = conn ->
        case sse_send(conn, data) do
          {:ok, new_conn} ->
            Process.put(:fp_sse_conn, new_conn)
            {:ok, new_conn}

          {:error, new_conn} ->
            Process.put(:fp_sse_conn, new_conn)
            {:error, new_conn}
        end

      _ ->
        {:error, nil}
    end
  end

  defp sse_send(conn, data) when is_map(data) do
    payload = format_sse_chunk(data)

    case Plug.Conn.chunk(conn, payload) do
      {:ok, conn} -> {:ok, conn}
      {:error, :closed} -> {:error, conn}
      {:error, _reason} -> {:error, conn}
    end
  end

  defp format_sse_chunk(data) do
    json = Jason.encode!(data)
    "data: " <> json <> "\n\n"
  end

  # Avoid pulling in UUID deps here; `unique_integer` is enough for demo IDs.
  defp unique_suffix do
    System.unique_integer([:positive, :monotonic]) |> Integer.to_string()
  end

  defp normalize_error(%{message: msg}) when is_binary(msg), do: msg
  defp normalize_error(msg) when is_binary(msg), do: msg
  defp normalize_error(other), do: inspect(other)
end
