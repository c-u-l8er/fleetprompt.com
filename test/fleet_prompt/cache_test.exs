defmodule FleetPrompt.CacheTest do
  use ExUnit.Case, async: false

  alias FleetPrompt.Cache

  setup do
    Cache.flush_all()
    :ok
  end

  describe "manifest cache" do
    test "put and get manifest" do
      agent_id = Ecto.UUID.generate()
      manifest = %{agent_id: agent_id, version: "1.0.0", name: "test-agent"}

      assert :ok = Cache.put_manifest(manifest)
      assert {:ok, ^manifest} = Cache.get_manifest(agent_id, "1.0.0")
    end

    test "returns :miss for unknown manifest" do
      assert :miss = Cache.get_manifest(Ecto.UUID.generate(), "1.0.0")
    end

    test "overwrites existing manifest" do
      agent_id = Ecto.UUID.generate()
      v1 = %{agent_id: agent_id, version: "1.0.0", name: "old"}
      v2 = %{agent_id: agent_id, version: "1.0.0", name: "updated"}

      Cache.put_manifest(v1)
      Cache.put_manifest(v2)

      assert {:ok, %{name: "updated"}} = Cache.get_manifest(agent_id, "1.0.0")
    end
  end

  describe "trust score cache" do
    test "put and get trust score" do
      agent_id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      assert :ok = Cache.put_trust_score(agent_id, 85, now)
      assert {:ok, 85, ^now} = Cache.get_trust_score(agent_id)
    end

    test "returns :miss for unknown agent" do
      assert :miss = Cache.get_trust_score(Ecto.UUID.generate())
    end
  end

  describe "category cache" do
    test "put and get category" do
      id1 = Ecto.UUID.generate()
      id2 = Ecto.UUID.generate()

      assert :ok = Cache.put_category("support", [id1, id2])
      assert {:ok, [^id1, ^id2]} = Cache.get_category("support")
    end

    test "returns :miss for unknown category" do
      assert :miss = Cache.get_category("nonexistent")
    end
  end

  describe "flush_all" do
    test "clears all caches" do
      agent_id = Ecto.UUID.generate()
      Cache.put_manifest(%{agent_id: agent_id, version: "1.0.0"})
      Cache.put_trust_score(agent_id, 90)
      Cache.put_category("test", [agent_id])

      assert :ok = Cache.flush_all()

      assert :miss = Cache.get_manifest(agent_id, "1.0.0")
      assert :miss = Cache.get_trust_score(agent_id)
      assert :miss = Cache.get_category("test")
    end
  end
end
