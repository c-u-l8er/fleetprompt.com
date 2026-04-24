defmodule FleetPrompt.InstallEngineTest do
  @moduledoc """
  Unit tests for the pure public helpers of `FleetPrompt.InstallEngine`
  — `resolve_mcp_dependencies/2`, `default_mcp_resolver/1`, and
  `audit_status/0`. These run without a DB.

  End-to-end `install/3` tests that touch `fleet.installs` /
  `fleet.audit_events` live in the DB-backed suite and are out of
  scope here.
  """
  use ExUnit.Case, async: true

  alias FleetPrompt.InstallEngine
  alias FleetPrompt.Manifests.Manifest

  # ---- audit_status/0 --------------------------------------------

  describe "audit_status/0" do
    test "reports all 7 steps with their implementation status" do
      steps = InstallEngine.audit_status()
      assert length(steps) == 7

      for i <- 1..7 do
        assert Enum.any?(steps, &(&1.step == i)), "missing step #{i}"
      end
    end

    test "exactly 4 steps are implemented; 3 are stubbed" do
      steps = InstallEngine.audit_status()

      implemented = Enum.count(steps, &(&1.status == :implemented))
      stubbed = Enum.count(steps, &(&1.status == :stubbed))

      assert implemented == 4
      assert stubbed == 3
    end

    test "stubbed steps each carry a TODO-like note" do
      InstallEngine.audit_status()
      |> Enum.filter(&(&1.status == :stubbed))
      |> Enum.each(fn step ->
        assert is_binary(step.note) and String.length(step.note) > 0
      end)
    end
  end

  # ---- default_mcp_resolver/1 ------------------------------------

  describe "default_mcp_resolver/1" do
    test "accepts a well-formed server map with url" do
      assert {:ok, "declared_only"} =
               InstallEngine.default_mcp_resolver(%{"name" => "graphonomous", "url" => "http://x/mcp"})
    end

    test "accepts atom-keyed server map" do
      assert {:ok, _} =
               InstallEngine.default_mcp_resolver(%{name: "graphonomous", url: "http://x/mcp"})
    end

    test "errors when url is missing" do
      assert {:error, :missing_url} = InstallEngine.default_mcp_resolver(%{"name" => "x"})
    end

    test "errors when url is empty" do
      assert {:error, :missing_url} = InstallEngine.default_mcp_resolver(%{"name" => "x", "url" => ""})
    end

    test "errors on non-map input" do
      assert {:error, :malformed_server_entry} = InstallEngine.default_mcp_resolver("not a map")
    end
  end

  # ---- resolve_mcp_dependencies/2 --------------------------------

  describe "resolve_mcp_dependencies/2" do
    defp manifest_with_servers(servers),
      do: %Manifest{mcp_servers: servers}

    test "returns [] when manifest has no mcp_servers" do
      assert {:ok, []} = InstallEngine.resolve_mcp_dependencies(manifest_with_servers([]), [])
    end

    test "returns status=declared_only for each valid server" do
      servers = [
        %{"name" => "graphonomous", "url" => "http://gh/mcp", "required" => true},
        %{"name" => "pulse", "url" => "http://pulse/mcp", "required" => false}
      ]

      assert {:ok, results} =
               InstallEngine.resolve_mcp_dependencies(manifest_with_servers(servers), [])

      assert length(results) == 2
      assert Enum.all?(results, &(&1["status"] == "declared_only"))
    end

    test "skip_mcp_check: true short-circuits and returns []" do
      servers = [%{"name" => "x", "url" => "http://x", "required" => true}]

      assert {:ok, []} =
               InstallEngine.resolve_mcp_dependencies(
                 manifest_with_servers(servers),
                 skip_mcp_check: true
               )
    end

    test "blocks install when a required server is unreachable" do
      servers = [
        %{"name" => "graphonomous", "url" => "http://gh/mcp", "required" => true},
        %{"name" => "dead-server", "url" => "http://dead", "required" => true}
      ]

      # Custom resolver: "dead-server" is unreachable
      resolver = fn server ->
        if server["name"] == "dead-server", do: {:error, :connection_refused}, else: {:ok, "reachable"}
      end

      assert {:error, {:mcp_dependencies_unreachable, missing}} =
               InstallEngine.resolve_mcp_dependencies(
                 manifest_with_servers(servers),
                 mcp_resolver: resolver
               )

      assert length(missing) == 1
      assert hd(missing)["name"] == "dead-server"
    end

    test "does NOT block install when an optional server is unreachable" do
      servers = [
        %{"name" => "graphonomous", "url" => "http://gh/mcp", "required" => true},
        %{"name" => "optional-server", "url" => "http://dead", "required" => false}
      ]

      resolver = fn server ->
        if server["required"], do: {:ok, "reachable"}, else: {:error, :connection_refused}
      end

      assert {:ok, results} =
               InstallEngine.resolve_mcp_dependencies(
                 manifest_with_servers(servers),
                 mcp_resolver: resolver
               )

      optional = Enum.find(results, &(&1["name"] == "optional-server"))
      assert optional["status"] == "unreachable"
    end

    test "preserves the name/url/required/status fields for every server" do
      servers = [
        %{"name" => "graphonomous", "url" => "http://x/mcp", "required" => true}
      ]

      {:ok, [result]} =
        InstallEngine.resolve_mcp_dependencies(manifest_with_servers(servers), [])

      assert result["name"] == "graphonomous"
      assert result["url"] == "http://x/mcp"
      assert result["required"] == true
      assert is_binary(result["status"])
    end
  end
end
