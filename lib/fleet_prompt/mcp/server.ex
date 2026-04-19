defmodule FleetPrompt.MCP.Server do
  @moduledoc """
  MCP JSON-RPC server for the FleetPrompt registry.

  Implements MCP protocol v2025-03-26 over HTTP.
  Exposes 7 tools for agent marketplace interaction:
  - registry_search, registry_publish, registry_install
  - registry_inspect, registry_versions, registry_trust, registry_fork
  """

  require Logger

  alias FleetPrompt.MCP.Tools

  @mcp_version "2025-03-26"
  @server_version Mix.Project.config()[:version]

  @doc """
  Handle an incoming JSON-RPC request.

  Returns a JSON-RPC response map, or nil for notifications.
  """
  @spec handle_request(map()) :: map() | nil
  def handle_request(%{"jsonrpc" => "2.0", "method" => method, "id" => id} = request) do
    params = Map.get(request, "params", %{})

    case dispatch(method, params) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, code, message} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => method}) do
    # Notification (no id) — no response needed
    dispatch(method, %{})
    nil
  end

  def handle_request(_) do
    %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32600, "message" => "Invalid Request"}
    }
  end

  @doc """
  Return the server's capabilities for the `initialize` handshake.
  """
  def capabilities do
    %{
      "protocolVersion" => @mcp_version,
      "serverInfo" => %{
        "name" => "fleetprompt",
        "version" => @server_version
      },
      "capabilities" => %{
        "tools" => %{"listChanged" => false}
      }
    }
  end

  @doc """
  List all available tools (for tools/list).
  """
  def list_tools do
    Tools.definitions()
  end

  # --- Dispatch ---

  defp dispatch("initialize", _params) do
    {:ok, capabilities()}
  end

  defp dispatch("tools/list", _params) do
    {:ok, %{"tools" => list_tools()}}
  end

  defp dispatch("tools/call", %{"name" => tool_name, "arguments" => args}) do
    call_tool(tool_name, args)
  end

  defp dispatch("tools/call", %{"name" => tool_name}) do
    call_tool(tool_name, %{})
  end

  defp dispatch(method, _params) do
    {:error, -32601, "Method not found: #{method}"}
  end

  defp call_tool(tool_name, args) do
    case Tools.call(tool_name, args) do
      {:ok, result} ->
        {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(result)}]}}

      {:error, message} when is_binary(message) ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => message}],
           "isError" => true
         }}

      {:error, other} ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => inspect(other)}],
           "isError" => true
         }}
    end
  rescue
    e ->
      Logger.error("MCP tool error: #{Exception.format(:error, e, __STACKTRACE__)}")

      {:ok,
       %{
         "content" => [%{"type" => "text", "text" => Exception.message(e)}],
         "isError" => true
       }}
  end
end
