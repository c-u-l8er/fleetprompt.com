defmodule FleetPromptWeb.MCPController do
  @moduledoc """
  HTTP endpoint for the FleetPrompt MCP JSON-RPC server.

  Delegates to `FleetPrompt.MCP.Server.handle_request/1`.
  """

  use FleetPromptWeb, :controller

  alias FleetPrompt.MCP.Server

  def handle(conn, params) do
    case Server.handle_request(params) do
      nil ->
        # Notification — no response
        send_resp(conn, 204, "")

      response ->
        json(conn, response)
    end
  end
end
