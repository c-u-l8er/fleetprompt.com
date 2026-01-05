defmodule FleetPromptWeb.ChatController do
  @moduledoc """
  Chat controller with an SSE streaming endpoint.

  This is intentionally lightweight right now:
  - `index/2` renders the Inertia `Chat` page with a minimal starter payload.
  - `send_message/2` streams a response over Server-Sent Events (SSE).

  Notes:
  - This controller does *not* persist conversations/messages yet. Phase 3 introduces
    Ash resources for `Conversation` + `Message` and a real intent/LLM pipeline.
  - The SSE payload format is designed to be easy for the Svelte client to parse:
    each event is a JSON object sent as an SSE `data:` line.
  """

  use FleetPromptWeb, :controller

  require Logger

  @sse_content_type "text/event-stream"

  # GET /chat
  #
  # You may currently be routing `/chat` to `PageController.chat/2`.
  # Once you switch the route to this controller, the UI can receive starter props.
  def index(conn, _params) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Chat", %{
      initialMessages: [
        %{
          id: "msg_welcome",
          role: "assistant",
          content:
            "Welcome to FleetPrompt Chat. This is a placeholder streaming endpoint for now — Phase 3 will add persistence and real model responses.",
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
      |> stream_demo_response(content)
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

  # This is a placeholder streaming implementation.
  # It demonstrates the end-to-end mechanics of SSE without any external dependencies.
  defp stream_demo_response(conn, user_message) do
    started_at = DateTime.utc_now()

    Logger.debug("[Chat] streaming demo response", user_message: user_message)

    conn =
      case sse_send(conn, %{type: "start", at: DateTime.to_iso8601(started_at)}) do
        {:ok, conn} -> conn
        {:error, conn} -> conn
      end

    # Stream a few chunks to prove incremental rendering works.
    chunks = [
      "Got it. You said: ",
      user_message,
      "\n\nThis endpoint is currently a demo SSE stream. Next we’ll wire it to real chat resources + an LLM client."
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
end
