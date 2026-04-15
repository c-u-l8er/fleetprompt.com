defmodule FleetPrompt.MCP.Server do
  @moduledoc """
  MCP JSON-RPC server for the FleetPrompt registry.

  Exposes 7 tools via the MCP protocol (v2025-03-26):
  - registry_search, registry_publish, registry_install
  - registry_inspect, registry_versions, registry_trust, registry_fork

  This is a stub — will be wired to an MCP transport (HTTP or STDIO)
  in Phase 7 implementation.
  """

  alias FleetPrompt.MCP.Tools

  @doc "Handle a tools/list request."
  def handle_tools_list do
    {:ok, %{tools: Tools.definitions()}}
  end

  @doc "Handle a tools/call request."
  def handle_tools_call(tool_name, arguments) do
    case Tools.call(tool_name, arguments) do
      {:ok, result} ->
        {:ok, %{content: [%{type: "text", text: Jason.encode!(result)}]}}

      {:error, message} ->
        {:error, %{content: [%{type: "text", text: message}], isError: true}}
    end
  end
end
