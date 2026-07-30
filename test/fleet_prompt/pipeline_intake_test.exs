defmodule FleetPrompt.PipelineIntakeTest do
  @moduledoc """
  The rejection cases below are cheap and were the whole of this file. They
  never published anything, so nothing here could show that the happy path
  worked — and it did not: the envelope's `workspace_id` was validated on the
  way in and then dropped before the publish, so an event naming a workspace
  but no agent was refused for having no workspace.

  A suite made only of refusals is green whatever the accept path does.
  """
  use FleetPrompt.DataCase, async: true

  alias FleetPrompt.PipelineIntake
  alias Kiln.Audit.Event

  defp insert_workspace! do
    slug = "ws-intake-#{System.unique_integer([:positive])}"

    {:ok, %{rows: [[id]]}} =
      Repo.query(
        "INSERT INTO amp.workspaces (name, slug) VALUES ($1, $2) RETURNING id::text",
        [slug, slug]
      )

    id
  end

  defp event(data) do
    slug = "intake-#{System.unique_integer([:positive])}"

    %{
      "type" => "com.agentelic.consolidation.v1",
      "data" =>
        Map.merge(
          %{
            "name" => slug,
            "slug" => slug,
            "version" => "1.0.0",
            "description" => "built by the dark factory",
            "spec_hash" => "sha256:deadbeef",
            "permissions" => [
              %{"capability" => "read", "scope" => "read", "reason" => "testing"}
            ]
          },
          data
        )
    }
  end

  describe "process/1 rejections" do
    test "rejects events without type" do
      assert {:error, :missing_event_type} = PipelineIntake.process(%{})
    end

    test "rejects unsupported event types" do
      assert {:error, {:unsupported_event_type, "com.example.unknown"}} =
               PipelineIntake.process(%{"type" => "com.example.unknown"})
    end

    test "rejects events without data" do
      assert {:error, :missing_event_data} =
               PipelineIntake.process(%{"type" => "com.agentelic.consolidation.v1"})
    end

    test "rejects events without spec_hash" do
      assert {:error, :missing_spec_hash} =
               PipelineIntake.process(%{
                 "type" => "com.agentelic.consolidation.v1",
                 "data" => %{"name" => "test"}
               })
    end

    test "rejects events with nil spec_hash" do
      assert {:error, :spec_not_registered} =
               PipelineIntake.process(%{
                 "type" => "com.agentelic.consolidation.v1",
                 "data" => %{"spec_hash" => nil}
               })
    end
  end

  describe "process/1 publishes" do
    test "an event carrying a workspace publishes without naming an agent" do
      # This is the case the dropped workspace_id broke. Agentelic builds
      # something; there is no marketplace listing for it yet, and there does
      # not need to be.
      workspace_id = insert_workspace!()

      assert {:ok, manifest} =
               PipelineIntake.process(event(%{"workspace_id" => workspace_id}))

      assert manifest.status == :published
      assert manifest.build_pipeline == "agentelic"

      # And it is attributable, which is the whole point of carrying the
      # workspace through.
      assert [audit] = Repo.all(from e in Event, where: e.target_id == ^manifest.id)
      assert audit.action == "publish"
      assert audit.workspace_id == workspace_id
    end

    test "an event with no workspace anywhere is refused, not silently published" do
      assert {:error, :missing_workspace_id} = PipelineIntake.process(event(%{}))
    end
  end
end
