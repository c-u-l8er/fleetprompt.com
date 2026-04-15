defmodule FleetPrompt.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias FleetPrompt.MCP.Server

  describe "handle_tools_list/0" do
    test "returns tools list" do
      assert {:ok, %{tools: tools}} = Server.handle_tools_list()
      assert length(tools) == 7
    end
  end

  describe "handle_tools_call/2" do
    test "returns error content for unknown tool" do
      assert {:error, %{content: [%{type: "text", text: msg}], isError: true}} =
               Server.handle_tools_call("unknown_tool", %{})

      assert msg =~ "Unknown tool"
    end
  end
end
