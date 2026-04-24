defmodule FleetPrompt.Skills.PollWorkerLiveTest do
  @moduledoc """
  Live end-to-end test of the skill-crystallization pipeline:

      Machine A records an InteractionTrace
          ↓   (store_trace MCP call)
      Graphonomous episodic memory
          ↓   (retrieve(replay) via GraphonomousClient.HTTP)
      FleetPrompt.Skills.PollWorker.crystallize_all/2
          ↓   (Crystallizer.from_trace → draft manifest + crystallization row)
      fleet.manifests + fleet.skill_crystallizations (Supabase)

  Requires a running Graphonomous MCP server. Default URL
  `http://127.0.0.1:4200/mcp`; override via `GRAPHONOMOUS_LIVE_URL`.
  The test seeds its own trace into Graphonomous so it is
  self-contained given a running server.

  Start Graphonomous locally before running:

      cd graphonomous && \\
        GRAPHONOMOUS_TRANSPORT=http \\
        GRAPHONOMOUS_PORT=4200 \\
        GRAPHONOMOUS_EMBEDDER_BACKEND=fallback \\
        mix run --no-halt &

      cd ../fleetprompt.com && \\
        mix test --include live_crystallization \\
          test/fleet_prompt/skills/poll_worker_live_test.exs

  Closes the ⚠️ on dark-factory step 4: "SkillCandidate crystallization
  has never been exercised with a real trace flowing through."
  """

  # async: false — mutates Application env (:graphonomous_client reverts
  # to the HTTP impl for this file) and performs real HTTP against a
  # live Graphonomous, so no parallelism with other tests.
  use FleetPrompt.DataCase, async: false

  @moduletag :live_crystallization

  alias FleetPrompt.Repo
  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Manifests.Manifest
  alias FleetPrompt.Publishers.Publisher
  alias FleetPrompt.Skills.{Crystallization, PollWorker}
  alias FleetPrompt.Skills.GraphonomousClient.HTTP, as: GHTTP

  @endpoint_default "http://127.0.0.1:4200/mcp"

  # ---- fixtures (mirror install_engine_db_test.exs) --------------

  defp insert_workspace! do
    slug = "ws-crys-#{System.unique_integer([:positive])}"

    {:ok, %{rows: [[id]]}} =
      Repo.query(
        "INSERT INTO amp.workspaces (name, slug) VALUES ($1, $2) RETURNING id::text",
        [slug, slug]
      )

    id
  end

  defp insert_publisher! do
    workspace_id = insert_workspace!()
    slug = "pub-crys-#{System.unique_integer([:positive])}"

    %Publisher{}
    |> Publisher.changeset(%{workspace_id: workspace_id, name: slug, slug: slug})
    |> Repo.insert!()
  end

  defp insert_agent!(publisher) do
    slug = "agent-crys-#{System.unique_integer([:positive])}"

    %Agent{}
    |> Agent.changeset(%{
      workspace_id: publisher.workspace_id,
      publisher_id: publisher.id,
      name: slug,
      slug: slug,
      description: "crystallization live test"
    })
    |> Repo.insert!()
  end

  # ---- Graphonomous trace seeding --------------------------------

  # Build a minimal OS-011 InteractionTrace that Graphonomous will
  # accept and Crystallizer can convert to a manifest.
  defp build_trace(trace_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "trace_id" => trace_id,
      "body_subtype" => "browser",
      "provider" => "agent-browser",
      "agent_id" => "live-crystallization-test",
      "started_at" => now,
      "ended_at" => now,
      "goal" => "Submit expense report via the corporate portal",
      "outcome" => "success",
      "environment" => %{},
      "metadata" => %{},
      "edges" => [
        %{
          "edge_id" => 0,
          "state_before" => "sha256:start-#{trace_id}",
          "state_after" => "sha256:mid-#{trace_id}",
          "typed_action" => %{"type" => "click", "target" => "@e1/g1"},
          "latency_ms" => 120,
          "outcome_status" => "success",
          "provenance" => %{"capability" => "&body.browser", "operation" => "act"}
        },
        %{
          "edge_id" => 1,
          "state_before" => "sha256:mid-#{trace_id}",
          "state_after" => "sha256:end-#{trace_id}",
          "typed_action" => %{
            "type" => "fill",
            "target" => "@e2/g1",
            "params" => %{"value" => "hello"}
          },
          "latency_ms" => 85,
          "outcome_status" => "success",
          "provenance" => %{"capability" => "&body.browser", "operation" => "act"}
        }
      ]
    }
  end

  defp endpoint do
    System.get_env("GRAPHONOMOUS_LIVE_URL") || @endpoint_default
  end

  # Seed the trace by calling Graphonomous's `act(action: "store_trace")`
  # tool directly over MCP (re-uses GraphonomousClient's session-aware
  # transport).
  defp seed_trace!(trace) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => System.unique_integer([:positive]),
        "method" => "tools/call",
        "params" => %{
          "name" => "act",
          "arguments" => %{
            "action" => "store_trace",
            "interaction_trace" => Jason.encode!(trace)
          }
        }
      })

    {:ok, resp_body} = GHTTP.default_transport(endpoint(), body, 5_000)
    decoded = Jason.decode!(resp_body)

    case get_in(decoded, ["result", "structuredContent"]) do
      %{"status" => "stored"} = sc -> {:ok, sc}
      other -> {:error, {:seed_failed, other, decoded}}
    end
  end

  # ---- setup -----------------------------------------------------

  setup do
    # Require a running Graphonomous; skip with a clear message
    # otherwise. We don't auto-start it because the test shouldn't
    # assume file-system access to the sibling repo.
    unless graphonomous_reachable?() do
      flunk("""
      Graphonomous MCP not reachable at #{endpoint()}.

      Start it before running these tests:

        cd graphonomous && \\
          GRAPHONOMOUS_TRANSPORT=http GRAPHONOMOUS_PORT=4200 \\
          GRAPHONOMOUS_EMBEDDER_BACKEND=fallback \\
          mix run --no-halt &
      """)
    end

    :ok
  end

  defp graphonomous_reachable? do
    health_url = endpoint() |> String.replace(~r{/mcp/?$}, "/health")
    _ = :inets.start()

    request = {String.to_charlist(health_url), []}

    case :httpc.request(:get, request, [timeout: 2_000, connect_timeout: 2_000], []) do
      {:ok, {{_, 200, _}, _headers, body}} -> to_string(body) =~ "graphonomous"
      _ -> false
    end
  end

  # ---- tests -----------------------------------------------------

  describe "live crystallization pipeline" do
    test "seeds a trace, crystallizes it, persists manifest + crystallization row" do
      publisher = insert_publisher!()
      agent = insert_agent!(publisher)
      trace_id = "trace-live-crys-#{System.unique_integer([:positive])}"

      trace = build_trace(trace_id)
      {:ok, _sc} = seed_trace!(trace)

      # Fetch the trace back via retrieve(replay) — same path the
      # PollWorker takes in production.
      {:ok, traces} =
        GHTTP.fetch_successful_traces(
          endpoint: endpoint(),
          trace_id: trace_id,
          limit: 1,
          timeout_ms: 5_000
        )

      assert length(traces) >= 1
      fetched = Enum.find(traces, &(&1["trace_id"] == trace_id))
      assert fetched, "seeded trace not returned by retrieve(replay)"

      args = %{"agent_id" => agent.id, "publisher_id" => publisher.id}

      assert {:ok, summary} = PollWorker.crystallize_all([fetched], args)

      assert summary.crystallized == 1
      assert summary.skipped == 0

      # Manifest row exists in fleet.manifests, as a :draft
      [manifest] = Repo.all(Manifest)
      assert manifest.agent_id == agent.id
      assert manifest.publisher_id == publisher.id
      assert manifest.status == :draft

      # Crystallization row exists with source_id == trace_id
      [crystallization] = Repo.all(Crystallization)
      assert crystallization.manifest_id == manifest.id
      assert crystallization.source_id == trace_id
      assert crystallization.source_type == :interaction_trace
    end

    test "crystallization is idempotent via (source_type, source_id) unique constraint" do
      publisher = insert_publisher!()
      agent = insert_agent!(publisher)
      trace_id = "trace-idem-#{System.unique_integer([:positive])}"

      trace = build_trace(trace_id)
      {:ok, _} = seed_trace!(trace)

      {:ok, [fetched | _]} =
        GHTTP.fetch_successful_traces(
          endpoint: endpoint(),
          trace_id: trace_id,
          limit: 1,
          timeout_ms: 5_000
        )

      args = %{"agent_id" => agent.id, "publisher_id" => publisher.id}

      # First run — crystallized
      assert {:ok, %{crystallized: 1, skipped: 0}} =
               PollWorker.crystallize_all([fetched], args)

      # Second run — skipped (idempotent)
      assert {:ok, %{crystallized: 0, skipped: 1}} =
               PollWorker.crystallize_all([fetched], args)

      # And only ONE crystallization row total
      assert Repo.aggregate(Crystallization, :count, :id) == 1
      assert Repo.aggregate(Manifest, :count, :id) == 1
    end
  end
end
