defmodule FleetPrompt.Skills.GraphonomousClientTest do
  @moduledoc """
  Unit tests for `FleetPrompt.Skills.GraphonomousClient.HTTP`.

  These cover:
    * `parse_response/1` against well-formed and malformed MCP payloads
    * `fetch_successful_traces/1` with an injected transport (no real HTTP)
    * `build_payload/4` JSON-RPC envelope shape
    * end-to-end hand-off into the Crystallizer (structural only)

  No network, no running Graphonomous — all deterministic.
  """

  use ExUnit.Case, async: true

  alias FleetPrompt.Skills.{Crystallizer, GraphonomousClient}
  alias FleetPrompt.Skills.GraphonomousClient.HTTP

  # ---- fixtures ---------------------------------------------------

  defp replay_envelope(trace_maps) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => 42,
      "result" => %{
        "content" => [],
        "structuredContent" => %{
          "status" => "ok",
          "count" => length(trace_maps),
          "traces" => trace_maps
        }
      }
    })
  end

  defp sample_trace_from_replay_manifest(trace_id) do
    %{
      "trace_id" => trace_id,
      "body_subtype" => "browser",
      "provider" => "agent-browser",
      "agent_id" => "test-agent",
      "started_at" => "2026-04-23T12:00:00Z",
      "ended_at" => "2026-04-23T12:00:05Z",
      "goal" => "Submit expense report",
      "outcome" => "success",
      "edge_count" => 1,
      "initial_state_hash" => "sha256:start",
      "replay_manifest" => %{
        "destructive" => false,
        "re_authorization_required" => false,
        "note" => nil,
        "edges" => [
          %{
            "edge_id" => 0,
            "state_before" => "sha256:start",
            "state_after" => "sha256:done",
            "typed_action" => %{"type" => "click", "target" => "@e1/g1"},
            "latency_ms" => 100,
            "outcome_status" => "success",
            "provenance" => %{"capability" => "&body.browser", "operation" => "act"}
          }
        ]
      }
    }
  end

  # ---- parse_response/1 -------------------------------------------

  describe "parse_response/1" do
    test "returns traces with edges hoisted from replay_manifest" do
      body = replay_envelope([sample_trace_from_replay_manifest("trace_a")])

      assert {:ok, [trace]} = HTTP.parse_response(body)
      assert trace["trace_id"] == "trace_a"
      # edges were inside replay_manifest; parser hoists them to top-level
      assert is_list(trace["edges"])
      assert length(trace["edges"]) == 1
      assert hd(trace["edges"])["typed_action"]["type"] == "click"
      # replay_manifest kept for downstream inspection
      assert is_map(trace["replay_manifest"])
    end

    test "passes through already-decoded map responses" do
      decoded =
        sample_trace_from_replay_manifest("trace_b")
        |> List.wrap()
        |> replay_envelope()
        |> Jason.decode!()

      assert {:ok, [trace]} = HTTP.parse_response(decoded)
      assert trace["trace_id"] == "trace_b"
    end

    test "returns jsonrpc_error for error envelopes" do
      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32601, "message" => "Method not found"}
        })

      assert {:error, {:jsonrpc_error, -32601, "Method not found"}} =
               HTTP.parse_response(body)
    end

    test "returns tool_error when structuredContent.status == error" do
      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "content" => [],
            "structuredContent" => %{
              "status" => "error",
              "error" => "not_found",
              "reason" => "no trace with trace_id=missing"
            }
          }
        })

      assert {:error, {:tool_error, "not_found", "no trace with trace_id=missing"}} =
               HTTP.parse_response(body)
    end

    test "falls back to content[].text when structuredContent is absent" do
      inner_json =
        Jason.encode!(%{
          "status" => "ok",
          "count" => 1,
          "traces" => [sample_trace_from_replay_manifest("trace_c")]
        })

      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "content" => [%{"type" => "text", "text" => inner_json}]
          }
        })

      assert {:ok, [trace]} = HTTP.parse_response(body)
      assert trace["trace_id"] == "trace_c"
      assert is_list(trace["edges"])
    end

    test "returns malformed_response on bad JSON" do
      assert {:error, {:malformed_response, _}} = HTTP.parse_response("not json")
    end

    test "returns unexpected_response_shape on an empty object" do
      assert {:error, {:unexpected_response_shape, _}} =
               HTTP.parse_response("{}")
    end

    test "handles an empty traces array" do
      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "content" => [],
            "structuredContent" => %{"status" => "ok", "count" => 0, "traces" => []}
          }
        })

      assert {:ok, []} = HTTP.parse_response(body)
    end
  end

  # ---- build_payload/4 --------------------------------------------

  describe "build_payload/4" do
    test "emits a valid JSON-RPC tools/call envelope for retrieve" do
      body = HTTP.build_payload("sha256:abc", nil, 5, "browser")
      decoded = Jason.decode!(body)

      assert decoded["jsonrpc"] == "2.0"
      assert is_integer(decoded["id"])
      assert decoded["method"] == "tools/call"
      assert decoded["params"]["name"] == "retrieve"

      args = decoded["params"]["arguments"]
      assert args["action"] == "replay"
      assert args["limit"] == 5
      assert args["state_hash"] == "sha256:abc"
      assert args["body_subtype"] == "browser"
      refute Map.has_key?(args, "trace_id")
    end

    test "omits nil arguments" do
      body = HTTP.build_payload(nil, nil, 10, nil)
      args = Jason.decode!(body) |> get_in(["params", "arguments"])

      assert args == %{"action" => "replay", "limit" => 10}
    end

    test "supports exact trace_id lookup" do
      body = HTTP.build_payload(nil, "trace_xyz", 1, nil)
      args = Jason.decode!(body) |> get_in(["params", "arguments"])

      assert args["trace_id"] == "trace_xyz"
      refute Map.has_key?(args, "state_hash")
    end
  end

  # ---- fetch_successful_traces/1 with injected transport ----------

  describe "fetch_successful_traces/1 with :transport injection" do
    test "round-trips a replay response via an injected transport" do
      trace = sample_trace_from_replay_manifest("trace_mcp_round_trip")
      envelope = replay_envelope([trace])

      captured = :ets.new(:captures, [:public])

      transport = fn url, body, _timeout ->
        :ets.insert(captured, {:url, url})
        :ets.insert(captured, {:body, body})
        {:ok, envelope}
      end

      opts = [
        endpoint: "http://fake/mcp",
        state_hash: "sha256:start",
        limit: 3,
        transport: transport
      ]

      assert {:ok, [returned]} = HTTP.fetch_successful_traces(opts)
      assert returned["trace_id"] == "trace_mcp_round_trip"
      assert is_list(returned["edges"])

      [{_, url}] = :ets.lookup(captured, :url)
      assert url == "http://fake/mcp"

      [{_, posted_body}] = :ets.lookup(captured, :body)
      decoded_body = Jason.decode!(posted_body)
      assert decoded_body["params"]["arguments"]["state_hash"] == "sha256:start"
      assert decoded_body["params"]["arguments"]["limit"] == 3

      :ets.delete(captured)
    end

    test "surfaces transport failures as :transport_failed" do
      transport = fn _url, _body, _timeout -> {:error, :nxdomain} end

      assert {:error, {:transport_failed, :nxdomain}} =
               HTTP.fetch_successful_traces(endpoint: "http://fake", transport: transport)
    end

    test "surfaces HTTP non-2xx as a status error" do
      transport = fn _, _, _ -> {:error, {:http_status, 500, "Server Error", "boom"}} end

      assert {:error, {:transport_failed, {:http_status, 500, _, _}}} =
               HTTP.fetch_successful_traces(endpoint: "http://fake", transport: transport)
    end

    test "surfaces malformed JSON responses" do
      transport = fn _, _, _ -> {:ok, "<html>not json</html>"} end

      assert {:error, {:malformed_response, _}} =
               HTTP.fetch_successful_traces(endpoint: "http://fake", transport: transport)
    end
  end

  # ---- End-to-end: HTTP output flows straight into Crystallizer ----

  describe "Crystallizer integration" do
    test "a trace fetched over HTTP can be crystallized without reshaping" do
      trace = sample_trace_from_replay_manifest("trace_e2e")
      envelope = replay_envelope([trace])
      transport = fn _, _, _ -> {:ok, envelope} end

      assert {:ok, [fetched]} =
               HTTP.fetch_successful_traces(endpoint: "http://fake", transport: transport)

      opts = [
        agent_id: Ecto.UUID.generate(),
        publisher_id: Ecto.UUID.generate(),
        source_endpoint: "http://fake"
      ]

      assert {:ok, %{manifest: mf, crystallization: cr}} =
               Crystallizer.from_trace(fetched, opts)

      assert mf.status == :draft
      assert cr.source_type == :interaction_trace
      assert cr.source_id == "trace_e2e"
      assert cr.edge_count == 1
    end
  end

  # ---- impl/0 configuration hook ---------------------------------

  describe "GraphonomousClient.impl/0" do
    test "defaults to the HTTP implementation" do
      assert GraphonomousClient.impl() == FleetPrompt.Skills.GraphonomousClient.HTTP
    end

    test "honors application config override" do
      original = Application.get_env(:fleet_prompt, :graphonomous_client)

      try do
        Application.put_env(
          :fleet_prompt,
          :graphonomous_client,
          FleetPrompt.Skills.GraphonomousClient.Stub
        )

        assert GraphonomousClient.impl() == FleetPrompt.Skills.GraphonomousClient.Stub
      after
        if is_nil(original) do
          Application.delete_env(:fleet_prompt, :graphonomous_client)
        else
          Application.put_env(:fleet_prompt, :graphonomous_client, original)
        end
      end
    end
  end
end
