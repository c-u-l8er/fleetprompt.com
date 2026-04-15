defmodule FleetPrompt.PipelineIntakeTest do
  use ExUnit.Case, async: true

  alias FleetPrompt.PipelineIntake

  describe "process/1" do
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
end
