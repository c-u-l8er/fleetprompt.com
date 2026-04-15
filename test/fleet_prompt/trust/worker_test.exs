defmodule FleetPrompt.Trust.WorkerTest do
  use ExUnit.Case, async: false

  alias FleetPrompt.Trust.Worker
  alias FleetPrompt.Cache

  setup do
    Cache.flush_all()
    :ok
  end

  describe "get_score/1" do
    test "returns :miss for agent with no cached score" do
      assert :miss = Worker.get_score(Ecto.UUID.generate())
    end

    test "returns cached score after put" do
      agent_id = Ecto.UUID.generate()
      now = DateTime.utc_now()
      Cache.put_trust_score(agent_id, 85, now)

      assert {:ok, 85, ^now} = Worker.get_score(agent_id)
    end
  end

  describe "ETS caching via Cache" do
    test "put_trust_score and get_trust_score round-trip" do
      agent_id = Ecto.UUID.generate()
      Cache.put_trust_score(agent_id, 72)

      assert {:ok, 72, _at} = Cache.get_trust_score(agent_id)
    end

    test "score updates overwrite previous values" do
      agent_id = Ecto.UUID.generate()
      Cache.put_trust_score(agent_id, 50)
      Cache.put_trust_score(agent_id, 90)

      assert {:ok, 90, _at} = Cache.get_trust_score(agent_id)
    end
  end
end
