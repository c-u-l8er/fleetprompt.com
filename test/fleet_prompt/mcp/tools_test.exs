defmodule FleetPrompt.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias FleetPrompt.MCP.Tools

  describe "definitions/0" do
    test "returns 7 tool definitions" do
      defs = Tools.definitions()
      assert length(defs) == 7
    end

    test "all tools have required fields" do
      for tool <- Tools.definitions() do
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.inputSchema)
        assert tool.inputSchema.type == "object"
      end
    end

    test "tool names match spec" do
      names = Tools.definitions() |> Enum.map(& &1.name) |> Enum.sort()

      expected =
        ~w(registry_fork registry_inspect registry_install registry_publish registry_search registry_trust registry_versions)

      assert names == expected
    end

    test "registry_search requires query param" do
      tool = Enum.find(Tools.definitions(), &(&1.name == "registry_search"))
      assert "query" in tool.inputSchema.required
    end

    test "registry_install requires agent_id, runtime_url, accept_permissions" do
      tool = Enum.find(Tools.definitions(), &(&1.name == "registry_install"))
      assert "agent_id" in tool.inputSchema.required
      assert "runtime_url" in tool.inputSchema.required
      assert "accept_permissions" in tool.inputSchema.required
    end
  end

  describe "call/2" do
    test "unknown tool returns error" do
      assert {:error, _} = Tools.call("nonexistent_tool", %{})
    end
  end
end
