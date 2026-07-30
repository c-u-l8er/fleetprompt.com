defmodule FleetPrompt.Manifests.AgentManifest do
  @moduledoc """
  The marketplace's claim on a manifest: "this agent, published by this
  publisher, is listing this manifest."

  This row is the whole of the marketplace's coupling to the engine. Before it
  existed, the same statement was made by two NOT NULL columns on the manifest
  itself, which meant the engine could not emit a manifest at all without a
  publisher row — the engine depended on the marketplace to produce the thing
  the marketplace lists.

  Nothing in the engine reads this table. A manifest with no row here is built
  but unlisted, and that is allowed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id
  @schema_prefix "fleet"

  schema "agent_manifests" do
    belongs_to :agent, FleetPrompt.Agents.Agent, primary_key: true
    belongs_to :manifest, Kiln.Manifests.Manifest, primary_key: true
    belongs_to :publisher, FleetPrompt.Publishers.Publisher

    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  @fields [:agent_id, :manifest_id, :publisher_id]

  def changeset(link, attrs) do
    link
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> unique_constraint([:agent_id, :manifest_id], name: "agent_manifests_pkey")
  end
end
