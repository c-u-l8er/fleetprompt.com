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

    test "all 7 steps are implemented; 0 are stubbed" do
      steps = InstallEngine.audit_status()

      implemented = Enum.count(steps, &(&1.status == :implemented))
      stubbed = Enum.count(steps, &(&1.status == :stubbed))

      assert implemented == 7
      assert stubbed == 0
    end

    test "Delegatic policy check (step 4) is implemented" do
      step = Enum.find(InstallEngine.audit_status(), &(&1.step == 4))

      assert step.status == :implemented
      assert String.contains?(step.note, "Delegatic")
    end

    test "OpenSentience deploy (step 5) is implemented" do
      step = Enum.find(InstallEngine.audit_status(), &(&1.step == 5))

      assert step.status == :implemented
      assert String.contains?(step.note, "Harness")
    end

    test "Graphonomous connect (step 6) is implemented" do
      step = Enum.find(InstallEngine.audit_status(), &(&1.step == 6))

      assert step.status == :implemented
      assert String.contains?(step.note, "telespace")
    end

    test "every step carries a non-empty note" do
      InstallEngine.audit_status()
      |> Enum.each(fn step ->
        assert is_binary(step.note) and String.length(step.note) > 0
      end)
    end
  end

  # ---- default_mcp_resolver/1 ------------------------------------

  describe "default_mcp_resolver/1" do
    test "accepts a well-formed server map with url" do
      assert {:ok, "declared_only"} =
               InstallEngine.default_mcp_resolver(%{
                 "name" => "graphonomous",
                 "url" => "http://x/mcp"
               })
    end

    test "accepts atom-keyed server map" do
      assert {:ok, _} =
               InstallEngine.default_mcp_resolver(%{name: "graphonomous", url: "http://x/mcp"})
    end

    test "errors when url is missing" do
      assert {:error, :missing_url} = InstallEngine.default_mcp_resolver(%{"name" => "x"})
    end

    test "errors when url is empty" do
      assert {:error, :missing_url} =
               InstallEngine.default_mcp_resolver(%{"name" => "x", "url" => ""})
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
        if server["name"] == "dead-server",
          do: {:error, :connection_refused},
          else: {:ok, "reachable"}
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

  # ---- delegatic_policy_check/2 ----------------------------------

  describe "delegatic_policy_check/2 (step 4)" do
    test "skips with :ok when no :delegatic_policy_id is supplied" do
      assert :ok = InstallEngine.delegatic_policy_check("ag-1", [])
    end

    test "returns :ok when policy allows the install action" do
      policy_id = "delegatic://test/install-ok-#{System.unique_integer([:positive])}"

      Delegatic.put_policy(
        Delegatic.Policy.new(%{
          policy_id: policy_id,
          allow_actions: ["install"],
          agents: ["ag-allowed"],
          max_ttl_seconds: 60
        })
      )

      opts = [delegatic_policy_id: policy_id, delegatic_approved_by: "supervisor@acme"]

      assert :ok = InstallEngine.delegatic_policy_check("ag-allowed", opts)
    end

    test "returns {:error, {:delegatic_denied, _}} when action is denied" do
      policy_id = "delegatic://test/install-deny-#{System.unique_integer([:positive])}"

      Delegatic.put_policy(
        Delegatic.Policy.new(%{
          policy_id: policy_id,
          allow_actions: ["read"],
          # "install" is NOT in allow_actions → :not_in_allowlist
          agents: ["ag-any"],
          max_ttl_seconds: 60
        })
      )

      opts = [delegatic_policy_id: policy_id]

      assert {:error, {:delegatic_denied, :not_in_allowlist}} =
               InstallEngine.delegatic_policy_check("ag-any", opts)
    end

    test "returns {:error, {:delegatic_denied, :agent_not_allowed}} for wrong agent" do
      policy_id = "delegatic://test/install-agent-#{System.unique_integer([:positive])}"

      Delegatic.put_policy(
        Delegatic.Policy.new(%{
          policy_id: policy_id,
          allow_actions: ["install"],
          agents: ["ag-allowed"],
          max_ttl_seconds: 60
        })
      )

      opts = [delegatic_policy_id: policy_id]

      assert {:error, {:delegatic_denied, :agent_not_allowed}} =
               InstallEngine.delegatic_policy_check("ag-not-on-list", opts)
    end

    test "returns {:error, {:delegatic_denied, :not_found}} for unknown policy" do
      opts = [
        delegatic_policy_id:
          "delegatic://test/does-not-exist-#{System.unique_integer([:positive])}"
      ]

      assert {:error, {:delegatic_denied, :not_found}} =
               InstallEngine.delegatic_policy_check("ag-1", opts)
    end
  end

  # ---- opensentience_deploy/3 (step 5) ---------------------------

  describe "opensentience_deploy/3 (step 5)" do
    test ":skipped when :skip_opensentience_deploy is true" do
      assert :skipped =
               InstallEngine.opensentience_deploy(
                 "ag-1",
                 "ws-1",
                 skip_opensentience_deploy: true
               )
    end

    test "honors :opensentience_deployer pluggable override on success" do
      deployer = fn %{agent_id: aid, workspace_id: wsid, opts: _opts} ->
        {:ok, %{validated: true, agent_id: aid, workspace_id: wsid, via: :stub}}
      end

      assert {:ok, %{validated: true, via: :stub}} =
               InstallEngine.opensentience_deploy(
                 "ag-1",
                 "ws-1",
                 opensentience_deployer: deployer
               )
    end

    test "honors :opensentience_deployer pluggable override on failure" do
      deployer = fn _ -> {:error, :deployer_rejected} end

      assert {:error, :deployer_rejected} =
               InstallEngine.opensentience_deploy(
                 "ag-1",
                 "ws-1",
                 opensentience_deployer: deployer
               )
    end

    test "default path: Harness.start_session + stop_session smoke succeeds" do
      # Exercises the real OpenSentience runtime (started via the
      # `:open_sentience` path dep's Application). A successful
      # transient session proves the Harness is loaded and accepts
      # the agent's configuration.
      assert {:ok, %{validated: true, agent_id: "ag-default-path"}} =
               InstallEngine.opensentience_deploy(
                 "ag-default-path",
                 "ws-default-path",
                 []
               )
    end

    test "session is torn down — no leaks after default-path deploy" do
      before = OpenSentience.Harness.active_sessions()

      {:ok, _} =
        InstallEngine.opensentience_deploy("ag-teardown", "ws-teardown", [])

      # Transient session should have been stopped synchronously.
      # Allow a tiny beat for DynamicSupervisor to process the exit.
      Process.sleep(20)
      after_count = OpenSentience.Harness.active_sessions()

      assert after_count == before
    end
  end

  # ---- graphonomous_connect/5 ------------------------------------

  describe "graphonomous_connect/5 (step 6)" do
    setup do
      # Route the default impl() lookup to the Stub for these tests.
      original = Application.get_env(:fleet_prompt, :graphonomous_client)

      Application.put_env(
        :fleet_prompt,
        :graphonomous_client,
        FleetPrompt.Skills.GraphonomousClient.Stub
      )

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:fleet_prompt, :graphonomous_client)
        else
          Application.put_env(:fleet_prompt, :graphonomous_client, original)
        end

        FleetPrompt.Skills.GraphonomousClient.Stub.put_telespace_result(
          {:ok, %{"node_id" => "stub-telespace", "endpoint" => "stub"}}
        )
      end)

      :ok
    end

    test ":skipped when :skip_graphonomous_connect is true" do
      assert :skipped =
               InstallEngine.graphonomous_connect(
                 "ag-1",
                 "v-1",
                 "ws-1",
                 "user-1",
                 skip_graphonomous_connect: true
               )
    end

    test "returns {:ok, ref} on stub success (non-fatal path)" do
      FleetPrompt.Skills.GraphonomousClient.Stub.put_telespace_result(
        {:ok, %{"node_id" => "node-abc", "endpoint" => "stub"}}
      )

      assert {:ok, %{"node_id" => "node-abc"}} =
               InstallEngine.graphonomous_connect("ag-1", "v-1", "ws-1", "user-1", [])
    end

    test "returns {:error, _} without raising when client returns an error" do
      FleetPrompt.Skills.GraphonomousClient.Stub.put_telespace_result(
        {:error, {:transport_failed, :nxdomain}}
      )

      assert {:error, {:transport_failed, :nxdomain}} =
               InstallEngine.graphonomous_connect("ag-1", "v-1", "ws-1", "user-1", [])
    end
  end
end
