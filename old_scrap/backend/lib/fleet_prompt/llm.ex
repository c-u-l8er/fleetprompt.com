defmodule FleetPrompt.LLM do
  @moduledoc """
  FleetPrompt LLM facade.

  This module is the single entrypoint for making LLM calls from FleetPrompt code.
  It intentionally hides provider-specific HTTP details behind a small API.

  ## Supported providers
  - `:openrouter` (default): OpenRouter "OpenAI-compatible" Chat Completions API

  ## Configuration

  Set an API key via either:
  - runtime env var: `OPENROUTER_API_KEY`
  - or application env: `config :fleet_prompt, :openrouter_api_key, "..."`

  Optional (mostly for OpenRouter attribution headers):
  - `config :fleet_prompt, :openrouter_referer, "https://your-domain"`
  - `config :fleet_prompt, :openrouter_title, "FleetPrompt"`

  ## Notes
  - This module does not persist anything. Persisted execution records live elsewhere (e.g. in an Execution domain).
  - Streaming is supported via `stream_chat_completion/3` and expects an OpenAI-style SSE stream.
  """

  alias __MODULE__.Error

  require Logger

  @default_provider :openrouter
  @default_timeout_ms 30_000
  @default_max_tokens 1024
  @default_temperature 0.7

  @typedoc """
  A chat message in OpenAI-compatible format.

  Roles: "system" | "user" | "assistant" | (optionally) "tool".

  Tool calling (OpenAI-compatible) may include additional fields:
  - assistant messages may include `tool_calls`
  - tool messages include `tool_call_id`

  This facade intentionally allows these extra fields and passes them through
  to the provider.
  """
  @type chat_message :: %{
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:tool_call_id) => String.t(),
          optional(:tool_calls) => list() | map(),
          optional(:name) => String.t()
        }

  @typedoc "Options for chat completion."
  @type chat_opts ::
          [
            provider: :openrouter,
            model: String.t(),
            max_tokens: pos_integer(),
            temperature: number(),
            timeout_ms: non_neg_integer(),
            # For streaming: request usage in-stream (provider-dependent).
            include_usage: boolean(),
            # Optional OpenAI-compatible fields (passed through)
            top_p: number(),
            frequency_penalty: number(),
            presence_penalty: number(),
            stop: [String.t()] | String.t(),
            response_format: map(),
            tools: [map()],
            tool_choice: String.t() | map()
          ]

  defmodule Error do
    @moduledoc false

    defexception [:message, :provider, :status, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            provider: atom() | nil,
            status: non_neg_integer() | nil,
            details: map() | nil
          }

    def new(message, opts \\ []) when is_binary(message) and is_list(opts) do
      %__MODULE__{
        message: message,
        provider: Keyword.get(opts, :provider),
        status: Keyword.get(opts, :status),
        details: Keyword.get(opts, :details)
      }
    end
  end

  @doc """
  Perform a non-streaming chat completion.

  Returns:
  - `{:ok, %{content: binary(), raw: map(), usage: map() | nil, model: binary(), provider: atom()}}`
  - `{:error, %FleetPrompt.LLM.Error{...}}`

  `messages` should be a list of `%{role: "...", content: "..."}` maps.
  """
  @spec chat_completion([chat_message()], chat_opts()) ::
          {:ok, map()} | {:error, Error.t()}
  def chat_completion(messages, opts \\ []) when is_list(messages) and is_list(opts) do
    provider = Keyword.get(opts, :provider, @default_provider)

    case provider do
      :openrouter ->
        openrouter_chat_completion(messages, opts)

      other ->
        {:error, Error.new("unsupported LLM provider", provider: other)}
    end
  end

  @doc """
  Perform a streaming chat completion.

  `on_event` receives:
  - `{:chunk, binary()}` for incremental text deltas
  - `{:complete, meta}` when the stream ends (best-effort metadata)

  Returns:
  - `{:ok, %{provider: atom(), model: binary()}}` if the stream request was initiated
  - `{:error, %FleetPrompt.LLM.Error{...}}` on failure

  Notes:
  - This uses Finch streaming to avoid buffering large responses in memory.
  - OpenRouter streams an OpenAI-style SSE payload (`data: {...}\\n\\n` and `data: [DONE]`).
  """
  @spec stream_chat_completion([chat_message()], (term() -> any()), chat_opts()) ::
          {:ok, map()} | {:error, Error.t()}
  def stream_chat_completion(messages, on_event, opts \\ [])
      when is_list(messages) and is_function(on_event, 1) and is_list(opts) do
    provider = Keyword.get(opts, :provider, @default_provider)

    case provider do
      :openrouter ->
        openrouter_stream_chat_completion(messages, on_event, opts)

      other ->
        {:error, Error.new("unsupported LLM provider", provider: other)}
    end
  end

  # -----------------------
  # OpenRouter implementation
  # -----------------------

  defp openrouter_chat_completion(messages, opts) do
    with {:ok, api_key} <- openrouter_api_key(),
         {:ok, normalized_messages} <- normalize_messages(messages) do
      model = Keyword.get(opts, :model, "openai/gpt-4o-mini")

      body =
        %{
          model: model,
          messages: normalized_messages,
          max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
          temperature: Keyword.get(opts, :temperature, @default_temperature)
        }
        |> maybe_put_opt(:top_p, opts)
        |> maybe_put_opt(:frequency_penalty, opts)
        |> maybe_put_opt(:presence_penalty, opts)
        |> maybe_put_opt(:stop, opts)
        |> maybe_put_opt(:response_format, opts)
        |> maybe_put_opt(:tools, opts)
        |> maybe_put_opt(:tool_choice, opts)

      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

      url = openrouter_chat_completions_url()
      headers = openrouter_headers(api_key)

      request =
        Finch.build(
          :post,
          url,
          headers,
          Jason.encode!(body)
        )

      case Finch.request(request, FleetPrompt.Finch, receive_timeout: timeout_ms) do
        {:ok, %Finch.Response{status: status, body: raw_body}} when status in 200..299 ->
          case decode_json(raw_body) do
            {:ok, decoded} ->
              case extract_openai_like_content(decoded) do
                {:ok, content} ->
                  {:ok,
                   %{
                     provider: :openrouter,
                     model: model,
                     content: content,
                     usage: Map.get(decoded, "usage"),
                     raw: decoded
                   }}

                {:error, %Error{} = err} ->
                  {:error, err}
              end

            {:error, decode_err} ->
              {:error,
               Error.new("failed to decode LLM response JSON",
                 provider: :openrouter,
                 details: %{error: decode_err}
               )}
          end

        {:ok, %Finch.Response{status: status, body: raw_body}} ->
          {:error, openai_like_http_error(:openrouter, status, raw_body)}

        {:error, reason} ->
          {:error,
           Error.new("LLM HTTP request failed",
             provider: :openrouter,
             details: %{reason: inspect(reason)}
           )}
      end
    end
  end

  defp openrouter_stream_chat_completion(messages, on_event, opts) do
    with {:ok, api_key} <- openrouter_api_key(),
         {:ok, normalized_messages} <- normalize_messages(messages) do
      model = Keyword.get(opts, :model, "openai/gpt-4o-mini")

      include_usage? = Keyword.get(opts, :include_usage, false)

      body =
        %{
          model: model,
          messages: normalized_messages,
          max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
          temperature: Keyword.get(opts, :temperature, @default_temperature),
          stream: true
        }
        |> maybe_put_stream_options(include_usage?)
        |> maybe_put_opt(:top_p, opts)
        |> maybe_put_opt(:frequency_penalty, opts)
        |> maybe_put_opt(:presence_penalty, opts)
        |> maybe_put_opt(:stop, opts)
        |> maybe_put_opt(:response_format, opts)
        |> maybe_put_opt(:tools, opts)
        |> maybe_put_opt(:tool_choice, opts)

      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

      url = openrouter_chat_completions_url()

      # For streaming, we also ask for text/event-stream explicitly.
      headers =
        openrouter_headers(api_key) ++
          [
            {"accept", "text/event-stream"}
          ]

      request =
        Finch.build(
          :post,
          url,
          headers,
          Jason.encode!(body)
        )

      acc0 = %{
        status: nil,
        headers: [],
        buffer: "",
        done: false,
        usage: nil
      }

      stream_cb = fn
        {:status, status}, acc ->
          %{acc | status: status}

        {:headers, headers}, acc ->
          %{acc | headers: headers}

        {:data, data}, acc ->
          # OpenAI-style streams are SSE-ish text. Finch gives us raw binary chunks.
          if acc.done do
            acc
          else
            parse_sse_data_chunk(data, acc, on_event)
          end
      end

      case Finch.stream(request, FleetPrompt.Finch, acc0, stream_cb, receive_timeout: timeout_ms) do
        {:ok, acc} ->
          # If server ended without [DONE], finalize best-effort.
          if acc.done do
            :ok
          else
            on_event.({:complete, %{provider: :openrouter, model: model, usage: acc.usage}})
          end

          {:ok, %{provider: :openrouter, model: model}}

        {:error, reason} ->
          {:error,
           Error.new("LLM streaming request failed",
             provider: :openrouter,
             details: %{reason: inspect(reason)}
           )}
      end
    end
  end

  defp openrouter_chat_completions_url do
    Application.get_env(:fleet_prompt, :openrouter_base_url, "https://openrouter.ai/api/v1") <>
      "/chat/completions"
  end

  defp openrouter_api_key do
    key =
      System.get_env("OPENROUTER_API_KEY") ||
        Application.get_env(:fleet_prompt, :openrouter_api_key)

    if is_binary(key) and String.trim(key) != "" do
      {:ok, String.trim(key)}
    else
      {:error,
       Error.new("missing OpenRouter API key (set OPENROUTER_API_KEY or :openrouter_api_key)",
         provider: :openrouter
       )}
    end
  end

  defp openrouter_headers(api_key) do
    referer = Application.get_env(:fleet_prompt, :openrouter_referer)
    title = Application.get_env(:fleet_prompt, :openrouter_title)

    base = [
      {"authorization", "Bearer " <> api_key},
      {"content-type", "application/json"}
    ]

    base
    |> maybe_add_header("http-referer", referer)
    |> maybe_add_header("x-title", title)
  end

  defp maybe_add_header(headers, _name, value) when value in [nil, ""], do: headers

  defp maybe_add_header(headers, name, value) when is_binary(value) do
    headers ++ [{name, value}]
  end

  # -----------------------
  # SSE parsing (OpenAI-style)
  # -----------------------

  defp parse_sse_data_chunk(data, acc, on_event) when is_binary(data) do
    buffer = acc.buffer <> data

    # SSE events are separated by a blank line.
    parts = String.split(buffer, "\n\n")

    # Keep the last part as the new buffer (it may be incomplete).
    {events, rest} =
      case parts do
        [] -> {[], ""}
        [_only] -> {[], buffer}
        _ -> {Enum.slice(parts, 0, length(parts) - 1), List.last(parts) || ""}
      end

    acc =
      Enum.reduce(events, %{acc | buffer: rest}, fn event, a ->
        handle_sse_event(event, a, on_event)
      end)

    acc
  end

  defp handle_sse_event(event, acc, on_event) when is_binary(event) do
    payloads =
      event
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(fn line -> String.trim_leading(line, "data:") |> String.trim_leading() end)

    Enum.reduce(payloads, acc, fn payload, a ->
      cond do
        payload == "" ->
          a

        payload == "[DONE]" ->
          on_event.({:complete, %{provider: :openrouter, usage: a.usage}})
          %{a | done: true}

        true ->
          case Jason.decode(payload) do
            {:ok, decoded} ->
              # OpenAI streaming shape:
              # %{"choices" => [%{"delta" => %{"content" => "..."}, ...}], "usage" => ...?}
              choice = get_in(decoded, ["choices", Access.at(0)])
              delta = Map.get(choice || %{}, "delta", %{})
              chunk = Map.get(delta, "content")
              tool_calls = Map.get(delta, "tool_calls")

              if is_binary(chunk) and chunk != "" do
                on_event.({:chunk, chunk})
              end

              if is_list(tool_calls) and tool_calls != [] do
                on_event.({:tool_calls, tool_calls})
              end

              # Some providers optionally include usage in-stream (final event or periodic).
              usage = Map.get(decoded, "usage") || a.usage
              %{a | usage: usage}

            {:error, _} ->
              # Malformed data chunks shouldn't kill the stream; ignore.
              a
          end
      end
    end)
  end

  # -----------------------
  # Helpers
  # -----------------------

  defp normalize_messages(messages) when is_list(messages) do
    try do
      normalized = Enum.map(messages, &normalize_message!/1)
      {:ok, normalized}
    rescue
      e in ArgumentError ->
        {:error, Error.new(Exception.message(e))}
    end
  end

  defp normalize_message!(%{} = msg) do
    role = Map.get(msg, :role) || Map.get(msg, "role")
    content = Map.get(msg, :content) || Map.get(msg, "content")

    if is_nil(role) or is_nil(content) do
      raise ArgumentError, "invalid chat message (missing role/content): #{inspect(msg)}"
    end

    base = %{role: to_string(role), content: to_string(content)}

    base
    |> maybe_put_string(msg, :name)
    |> maybe_put_string(msg, :tool_call_id)
    |> maybe_put_raw(msg, :tool_calls)
  end

  defp normalize_message!(other) do
    raise ArgumentError, "invalid chat message: #{inspect(other)}"
  end

  defp maybe_put_string(acc, msg, key) do
    v = Map.get(msg, key) || Map.get(msg, Atom.to_string(key))

    if is_binary(v) and String.trim(v) != "" do
      Map.put(acc, key, v)
    else
      acc
    end
  end

  defp maybe_put_raw(acc, msg, key) do
    v = Map.get(msg, key) || Map.get(msg, Atom.to_string(key))

    if is_nil(v) do
      acc
    else
      Map.put(acc, key, v)
    end
  end

  defp maybe_put_opt(map, key, opts) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end

  defp maybe_put_stream_options(map, include_usage?) do
    if include_usage? do
      # OpenAI-compatible stream options; provider support may vary.
      Map.put(map, :stream_options, %{include_usage: true})
    else
      map
    end
  end

  defp decode_json(body) when is_binary(body) do
    Jason.decode(body)
  end

  defp decode_json(body) do
    {:error, "expected binary body, got: #{inspect(body)}"}
  end

  defp extract_openai_like_content(decoded) when is_map(decoded) do
    content =
      get_in(decoded, ["choices", Access.at(0), "message", "content"]) ||
        get_in(decoded, ["choices", Access.at(0), "text"])

    if is_binary(content) do
      {:ok, content}
    else
      {:error,
       Error.new("LLM response did not include choices[0].message.content",
         details: %{keys: Map.keys(decoded)}
       )}
    end
  end

  defp openai_like_http_error(provider, status, raw_body) do
    details =
      case decode_json(raw_body) do
        {:ok, decoded} -> decoded
        {:error, _} -> %{"raw_body" => raw_body}
      end

    # Common OpenAI-style error payload: %{"error" => %{"message" => "..."}}
    msg =
      get_in(details, ["error", "message"]) ||
        get_in(details, ["message"]) ||
        "LLM provider returned HTTP #{status}"

    Error.new(msg, provider: provider, status: status, details: details)
  end
end
