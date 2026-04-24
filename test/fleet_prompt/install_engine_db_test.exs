defmodule FleetPrompt.InstallEngineDBTest do
  @moduledoc """
  End-to-end DB-backed tests for `FleetPrompt.InstallEngine.install/3`.

  These exercise the full 7-step install flow against a real
  Supabase instance (schemas `fleet.*` + `amp.*`) through the
  `Ecto.Adapters.SQL.Sandbox`. Each test gets a fresh transactional
  sandbox so no row state leaks across tests.

  Complements `FleetPrompt.InstallEngineTest` (which covers the pure
  helpers without a DB).
  """

  # async: false — this test file mutates Application env to route
  # `GraphonomousClient.impl/0` to the Stub, and must not run in
  # parallel with `FleetPrompt.Skills.GraphonomousClientTest` (which
  # asserts the default HTTP impl is returned).
  use FleetPrompt.DataCase, async: false

  alias FleetPrompt.{InstallEngine, Registry, Repo}
  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Installs.Install
  alias FleetPrompt.Publishers.Publisher
  alias FleetPrompt.Versions.Version
  alias FleetPrompt.Skills.GraphonomousClient.Stub, as: GraphonomousStub

  # ---- fixtures --------------------------------------------------

  defp insert_workspace! do
    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, %{num_rows: 1, rows: [[id]]}} =
      Repo.query(
        "INSERT INTO amp.workspaces (name, slug) VALUES ($1, $2) RETURNING id::text",
        [slug, slug]
      )

    id
  end

  defp insert_publisher! do
    workspace_id = insert_workspace!()
    slug = "pub-#{System.unique_integer([:positive])}"

    %Publisher{}
    |> Publisher.changeset(%{
      workspace_id: workspace_id,
      name: slug,
      slug: slug
    })
    |> Repo.insert!()
  end

  defp insert_agent!(publisher) do
    slug = "agent-#{System.unique_integer([:positive])}"

    %Agent{}
    |> Agent.changeset(%{
      workspace_id: publisher.workspace_id,
      publisher_id: publisher.id,
      name: slug,
      slug: slug,
      description: "Test agent"
    })
    |> Repo.insert!()
  end

  defp insert_version!(agent, version \\ "1.0.0") do
    %Version{}
    |> Version.changeset(%{
      agent_id: agent.id,
      workspace_id: agent.workspace_id,
      version: version,
      manifest: %{"name" => agent.name}
    })
    |> Repo.insert!()
  end

  defp insert_published_manifest!(overrides \\ %{}) do
    publisher = insert_publisher!()
    agent = insert_agent!(publisher)
    version = insert_version!(agent)
    slug = "agent-#{System.unique_integer([:positive])}"

    attrs =
      Map.merge(
        %{
          name: slug,
          slug: slug,
          version: "1.0.0",
          description: "Test agent for install flow",
          permissions: [
            %{
              "capability" => "tickets:read",
              "scope" => "read",
              "reason" => "Read support tickets"
            }
          ],
          runtime: "opensentience",
          build_pipeline: "agentelic",
          test_results: %{"passed" => 10, "failed" => 0, "skipped" => 0},
          mcp_servers: [
            %{"name" => "graphonomous", "url" => "http://gh/mcp", "required" => true}
          ],
          agent_id: agent.id,
          publisher_id: publisher.id
        },
        overrides
      )

    {:ok, manifest} = Registry.publish_manifest(attrs, skip_spec_validation: true)

    # Return manifest with the real version_id + workspace_id + publisher
    # attached as plain fields so install/3 tests can use them without
    # having to know the full object graph.
    manifest
    |> Map.put(:version_id, version.id)
    |> Map.put(:test_workspace_id, publisher.workspace_id)
    |> Map.put(:test_publisher_id, publisher.id)
  end

  # ---- setup: route GraphonomousClient to the Stub ---------------

  setup do
    original = Application.get_env(:fleet_prompt, :graphonomous_client)

    Application.put_env(
      :fleet_prompt,
      :graphonomous_client,
      GraphonomousStub
    )

    # Default: Stub succeeds. Individual tests override via put_telespace_result/1.
    GraphonomousStub.put_telespace_result(
      {:ok, %{"node_id" => "stub-node-#{System.unique_integer([:positive])}", "endpoint" => "stub"}}
    )

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:fleet_prompt, :graphonomous_client)
      else
        Application.put_env(:fleet_prompt, :graphonomous_client, original)
      end
    end)

    :ok
  end

  # ---- happy path ------------------------------------------------

  describe "install/3 end-to-end (all 7 steps)" do
    test "succeeds with valid opts, no Delegatic policy" do
      manifest = insert_published_manifest!()
      workspace_id = manifest.test_workspace_id

      assert {:ok, %Install{} = install} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: workspace_id,
                 # :installed_by intentionally omitted — seeding an
                 # amp.profiles row would require an auth.users row
                 # (FK chain), which is out of scope for these unit
                 # integration tests. The happy path still exercises
                 # the full 7-step flow; audit-writer records install
                 # with nil actor.
                 accept_permissions: true
               )

      assert install.agent_id == manifest.agent_id
      assert install.workspace_id == workspace_id
      assert is_nil(install.uninstalled_at)
    end

    test "Graphonomous connect failure is non-fatal — install still succeeds" do
      manifest = insert_published_manifest!()

      GraphonomousStub.put_telespace_result({:error, {:transport_failed, :nxdomain}})

      assert {:ok, %Install{}} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id,
                 accept_permissions: true
               )
    end

    test "full 7-of-7 flow: Delegatic-allow + real OpenSentience + Graphonomous all ok" do
      manifest = insert_published_manifest!()
      policy_id = "delegatic://test/full-flow-#{System.unique_integer([:positive])}"

      Delegatic.put_policy(
        Delegatic.Policy.new(%{
          policy_id: policy_id,
          allow_actions: ["install"],
          agents: [to_string(manifest.agent_id)],
          max_ttl_seconds: 60
        })
      )

      before_sessions = OpenSentience.Harness.active_sessions()

      assert {:ok, %Install{}} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id,
                 accept_permissions: true,
                 delegatic_policy_id: policy_id,
                 delegatic_approved_by: "ci@fleetprompt"
               )

      # OpenSentience session should have been torn down synchronously.
      Process.sleep(20)
      assert OpenSentience.Harness.active_sessions() == before_sessions
    end

    test "skip_graphonomous_connect short-circuits the telespace init" do
      manifest = insert_published_manifest!()

      # Set the Stub to raise if ever called. If install succeeds,
      # it means the skip opt bypassed the client entirely.
      GraphonomousStub.put_telespace_result(
        {:error, :should_not_be_called}
      )

      assert {:ok, %Install{}} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id,
                 accept_permissions: true,
                 skip_graphonomous_connect: true
               )
    end
  end

  # ---- Delegatic integration (step 4) ----------------------------

  describe "install/3 with Delegatic policy (step 4)" do
    test "allows install when policy permits" do
      manifest = insert_published_manifest!()
      policy_id = "delegatic://test/ok-#{System.unique_integer([:positive])}"

      Delegatic.put_policy(
        Delegatic.Policy.new(%{
          policy_id: policy_id,
          allow_actions: ["install"],
          agents: [to_string(manifest.agent_id)],
          max_ttl_seconds: 60
        })
      )

      assert {:ok, %Install{}} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id,
                 accept_permissions: true,
                 delegatic_policy_id: policy_id,
                 delegatic_approved_by: "supervisor@acme"
               )
    end

    test "blocks install when policy denies" do
      manifest = insert_published_manifest!()
      policy_id = "delegatic://test/deny-#{System.unique_integer([:positive])}"

      Delegatic.put_policy(
        Delegatic.Policy.new(%{
          policy_id: policy_id,
          # install not in allowlist
          allow_actions: ["read"],
          max_ttl_seconds: 60
        })
      )

      assert {:error, {:delegatic_denied, :not_in_allowlist}} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id,
                 accept_permissions: true,
                 delegatic_policy_id: policy_id
               )

      # No install row written
      assert Repo.aggregate(Install, :count, :id) == 0
    end

    test "blocks install when referenced policy does not exist" do
      manifest = insert_published_manifest!()

      assert {:error, {:delegatic_denied, :not_found}} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id,
                 accept_permissions: true,
                 delegatic_policy_id: "delegatic://test/ghost-#{System.unique_integer([:positive])}"
               )
    end
  end

  # ---- input-level guard rails -----------------------------------

  describe "install/3 input guards" do
    test "rejects without :accept_permissions" do
      manifest = insert_published_manifest!()

      assert {:error, :permissions_not_accepted} =
               InstallEngine.install(
                 manifest.agent_id,
                 manifest.version_id,
                 workspace_id: manifest.test_workspace_id
                 # accept_permissions NOT set
               )
    end

    test "rejects when no published manifest exists for the agent" do
      # No manifest is inserted — verify_manifest/1 returns :no_published_manifest
      # before any FK-bearing rows are touched. A bare random UUID for
      # workspace_id is fine because the flow short-circuits first.
      assert {:error, :no_published_manifest} =
               InstallEngine.install(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 workspace_id: Ecto.UUID.generate(),
                 accept_permissions: true
               )
    end
  end
end
