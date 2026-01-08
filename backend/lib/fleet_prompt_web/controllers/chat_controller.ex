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
  # Expects JSON body like: { "message": "hello" }
  #
  # Responds with SSE:
  #   data: {"type":"chunk","chunk":"..."}
  #   data: {"type":"complete","message":{...}}
  def send_message(conn, %{"message" => content}) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "message cannot be empty"})
    else
      conn
      |> prepare_sse()
      |> stream_llm_response(content)
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
  defp stream_llm_response(conn, user_message) do
    started_at = DateTime.utc_now()
    now_iso = DateTime.to_iso8601(started_at)

    # IMPORTANT: Plug.Conn is immutable; chunking returns an updated conn each time.
    # Because the LLM streaming callback runs asynchronously within this request,
    # we store and update the conn in the process dictionary so every chunk uses
    # the latest conn struct.
    Process.put(:fp_sse_conn, conn)
    _ = sse_send_pd(%{type: "start", at: now_iso})

    Process.put(:fp_llm_acc, "")

    messages = [
      %{
        role: "system",
        content:
          "You are FleetPrompt’s assistant. Be concise and helpful. Do not claim you performed actions you did not perform. If configuration is missing, say so."
      },
      %{role: "user", content: user_message}
    ]

    opts = [
      provider: :openrouter,
      model: llm_default_model(),
      max_tokens: 800,
      temperature: 0.3,
      timeout_ms: 30_000,
      include_usage: true
    ]

    on_event = fn
      {:chunk, chunk} when is_binary(chunk) and chunk != "" ->
        acc = Process.get(:fp_llm_acc, "")
        Process.put(:fp_llm_acc, acc <> chunk)

        _ = sse_send_pd(%{type: "chunk", chunk: chunk})
        :ok

      {:complete, meta} ->
        finished_at = DateTime.utc_now()
        content = Process.get(:fp_llm_acc, "")

        final_message = %{
          id: "assistant_" <> unique_suffix(),
          role: "assistant",
          content: content,
          actions: [],
          inserted_at: DateTime.to_iso8601(finished_at)
        }

        _ =
          sse_send_pd(%{
            type: "complete",
            message: final_message,
            meta:
              Map.merge(
                %{
                  started_at: now_iso,
                  finished_at: DateTime.to_iso8601(finished_at)
                },
                sanitize_llm_meta(meta)
              )
          })

        :ok

      _other ->
        :ok
    end

    case LLM.stream_chat_completion(messages, on_event, opts) do
      {:ok, _info} ->
        Process.get(:fp_sse_conn, conn)

      {:error, err} ->
        Logger.warning("[Chat] LLM stream failed; falling back to demo SSE",
          error: normalize_error(err)
        )

        stream_demo_response(Process.get(:fp_sse_conn, conn), user_message, err)
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
