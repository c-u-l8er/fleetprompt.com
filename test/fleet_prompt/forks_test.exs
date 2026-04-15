defmodule FleetPrompt.ForksTest do
  use ExUnit.Case, async: true

  alias FleetPrompt.Manifests.Manifest

  describe "fork manifest validation" do
    test "forked manifest starts as draft" do
      changeset =
        Manifest.changeset(%Manifest{}, %{
          name: "test-agent (fork)",
          slug: "test-agent-fork",
          version: "0.1.0",
          description: "Forked agent",
          permissions: [],
          agent_id: Ecto.UUID.generate(),
          publisher_id: Ecto.UUID.generate(),
          forked_from: Ecto.UUID.generate(),
          status: :draft
        })

      assert changeset.valid?
      # :draft is the default, so it won't appear as a change unless explicitly set
      assert Ecto.Changeset.get_field(changeset, :status) == :draft
      assert Ecto.Changeset.get_change(changeset, :forked_from) != nil
    end

    test "forked manifest version starts at 0.1.0" do
      changeset =
        Manifest.changeset(%Manifest{}, %{
          name: "forked",
          slug: "forked",
          version: "0.1.0",
          description: "test",
          permissions: [],
          agent_id: Ecto.UUID.generate(),
          publisher_id: Ecto.UUID.generate(),
          forked_from: Ecto.UUID.generate()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :version) == "0.1.0"
    end
  end
end
