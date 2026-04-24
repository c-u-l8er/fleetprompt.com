defmodule FleetPrompt.Skills.GraphonomousClient do
  @moduledoc """
  Behaviour for fetching successful `InteractionTrace` records from a
  Graphonomous MCP server.

  The default implementation (`FleetPrompt.Skills.GraphonomousClient.HTTP`)
  makes MCP JSON-RPC calls against the configured endpoint via the
  Erlang stdlib `:httpc` client:

      FleetPrompt.Skills.GraphonomousClient.HTTP.fetch_successful_traces(
        endpoint: "https://graphonomous-mcp.fly.dev/mcp",
        state_hash: "sha256:...",
        limit: 10
      )

  Tests use `FleetPrompt.Skills.GraphonomousClient.Stub` or the HTTP
  impl with an injected transport (see
  `FleetPrompt.Skills.GraphonomousClient.HTTP.fetch_successful_traces/1`,
  `:transport` option). Override via application config:

      config :fleet_prompt, :graphonomous_client,
        FleetPrompt.Skills.GraphonomousClient.Stub

  No LLM calls happen here. This is a pure data-layer transport.
  """

  @type trace :: map()
  @type opts :: keyword()

  @callback fetch_successful_traces(opts()) :: {:ok, [trace()]} | {:error, term()}

  @doc "Resolve the configured client module (defaults to the HTTP impl)."
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :fleet_prompt,
      :graphonomous_client,
      FleetPrompt.Skills.GraphonomousClient.HTTP
    )
  end
end

defmodule FleetPrompt.Skills.GraphonomousClient.HTTP do
  @moduledoc """
  Default HTTP implementation — issues MCP JSON-RPC `tools/call`
  requests against a Graphonomous server using `:httpc` from the
  standard library so no new runtime dependency is required.

  The response-parsing path and the transport path are separable:

    * `fetch_successful_traces/1` is the top-level entry point.
    * `parse_response/1` turns a raw JSON-RPC response body into a
      `{:ok, [trace()]}` / `{:error, term()}` — unit-testable with
      only a fixture string.
    * The transport (`:httpc.request`) is injectable via the
      `:transport` option so tests can substitute a fake.

  Each trace is returned in the shape the `FleetPrompt.Skills.Crystallizer`
  expects: `replay_manifest.edges` is hoisted to the top-level
  `"edges"` key so the Crystallizer's existing parser accepts the map
  unchanged.
  """

  @behaviour FleetPrompt.Skills.GraphonomousClient

  require Logger

  @default_timeout_ms 15_000

  @impl true
  def fetch_successful_traces(opts) do
    endpoint = Keyword.get(opts, :endpoint) || default_endpoint()
    state_hash = Keyword.get(opts, :state_hash)
    trace_id = Keyword.get(opts, :trace_id)
    limit = Keyword.get(opts, :limit, 5)
    body_subtype = Keyword.get(opts, :body_subtype)
    transport = Keyword.get(opts, :transport, &default_transport/3)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    body = build_payload(state_hash, trace_id, limit, body_subtype)

    case transport.(endpoint, body, timeout) do
      {:ok, response_body} -> parse_response(response_body)
      {:error, reason} -> {:error, {:transport_failed, reason}}
    end
  end

  @doc """
  Parse a raw MCP JSON-RPC response body into a list of traces. Handles
  both string bodies and already-decoded maps. Public for testing.
  """
  @spec parse_response(binary() | map()) :: {:ok, [map()]} | {:error, term()}
  def parse_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_response(decoded)
      {:error, err} -> {:error, {:malformed_response, err}}
    end
  end

  def parse_response(%{"error" => %{"code" => code, "message" => msg}}) do
    {:error, {:jsonrpc_error, code, msg}}
  end

  def parse_response(%{"result" => result}) when is_map(result) do
    structured = Map.get(result, "structuredContent") || Map.get(result, :structured_content)

    cond do
      is_map(structured) and structured["status"] == "error" ->
        {:error, {:tool_error, structured["error"], structured["reason"]}}

      is_map(structured) and is_list(structured["traces"]) ->
        {:ok, Enum.map(structured["traces"], &flatten_trace/1)}

      # Some MCP transports deliver structured payloads inside the
      # content[].text field as an embedded JSON string. Fall through
      # to parse that.
      is_list(result["content"]) ->
        parse_from_content_array(result["content"])

      true ->
        {:error, {:unexpected_response_shape, Map.keys(result)}}
    end
  end

  def parse_response(other), do: {:error, {:unexpected_response_shape, other}}

  # Hoist replay_manifest.edges to the top level so downstream parsers
  # (e.g. FleetPrompt.Skills.Crystallizer) see the shape they expect.
  defp flatten_trace(trace) when is_map(trace) do
    manifest = Map.get(trace, "replay_manifest") || %{}
    edges = Map.get(manifest, "edges", Map.get(trace, "edges", []))

    trace
    |> Map.put("edges", edges)
    # Keep the replay_manifest around under a distinct key in case
    # downstream wants it (e.g. to check `destructive` or
    # `re_authorization_required`).
    |> Map.put_new("replay_manifest", manifest)
  end

  defp flatten_trace(other), do: other

  defp parse_from_content_array(content) do
    with %{"type" => "text", "text" => text} <- List.first(content) || %{},
         {:ok, decoded} <- Jason.decode(text),
         true <- is_map(decoded) and is_list(decoded["traces"]) do
      {:ok, Enum.map(decoded["traces"], &flatten_trace/1)}
    else
      _ -> {:error, {:unexpected_response_shape, :content_text}}
    end
  end

  @doc false
  # Public-ish for testing — builds the exact JSON-RPC payload we POST.
  @spec build_payload(String.t() | nil, String.t() | nil, integer(), String.t() | nil) :: binary()
  def build_payload(state_hash, trace_id, limit, body_subtype) do
    args =
      %{"action" => "replay", "limit" => limit}
      |> maybe_put("state_hash", state_hash)
      |> maybe_put("trace_id", trace_id)
      |> maybe_put("body_subtype", body_subtype)

    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "tools/call",
      "params" => %{
        "name" => "retrieve",
        "arguments" => args
      }
    })
  end

  @doc false
  # Default transport: HTTP POST via :httpc. Returns {:ok, body_bin}
  # or {:error, reason}. Tests inject their own.
  @spec default_transport(String.t(), binary(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  def default_transport(url, body, timeout) do
    ensure_inets_started()

    url_charlist = String.to_charlist(url)
    headers = [{~c"accept", ~c"application/json"}]
    content_type = ~c"application/json"

    request = {url_charlist, headers, content_type, body}

    http_opts = [
      timeout: timeout,
      connect_timeout: min(timeout, 5_000)
    ]

    opts = [body_format: :binary]

    case :httpc.request(:post, request, http_opts, opts) do
      {:ok, {{_, status, _}, _headers, resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, {{_, status, reason}, _headers, resp_body}} ->
        {:error, {:http_status, status, to_string(reason), resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_inets_started do
    # :httpc is part of the `inets` OTP app — production environments
    # already start it (Graphonomous does), but tests that exercise
    # this module directly may not.
    _ = :inets.start()
    _ = :ssl.start()
    :ok
  end

  defp default_endpoint do
    Application.get_env(
      :fleet_prompt,
      :graphonomous_endpoint,
      "https://graphonomous-mcp.fly.dev/mcp"
    )
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end

defmodule FleetPrompt.Skills.GraphonomousClient.Stub do
  @moduledoc """
  Test stub — returns whatever traces have been pre-seeded via
  `put_traces/1`. Used by the crystallization unit tests and by
  anyone who wants to run the poll worker end-to-end without a live
  Graphonomous MCP server.
  """

  @behaviour FleetPrompt.Skills.GraphonomousClient

  @table :fleet_prompt_graphonomous_stub

  @doc "Seed the stub with traces that will be returned on the next fetch."
  def put_traces(traces) when is_list(traces) do
    ensure_table()
    :ets.insert(@table, {:traces, traces})
    :ok
  end

  @doc "Clear all seeded traces."
  def clear do
    ensure_table()
    :ets.delete(@table, :traces)
    :ok
  end

  @impl true
  def fetch_successful_traces(_opts) do
    ensure_table()

    case :ets.lookup(@table, :traces) do
      [{:traces, list}] when is_list(list) -> {:ok, list}
      _ -> {:ok, []}
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ok
    end
  end
end
