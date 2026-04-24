defmodule FleetPrompt.Versions.Version do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "fleet"

  schema "agent_versions" do
    belongs_to :agent, FleetPrompt.Agents.Agent

    field :workspace_id, :binary_id
    field :version, :string
    field :manifest, :map
    field :readme, :string
    field :changelog, :string
    field :permissions, {:array, :string}, default: []
    field :mcp_tools, {:array, :string}, default: []
    field :artifact_url, :string
    field :artifact_hash, :string
    field :artifact_size, :integer
    field :published_by, :binary_id
    field :published_at, :utc_datetime
    field :yanked, :boolean, default: false

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :agent_id,
      :workspace_id,
      :version,
      :manifest,
      :readme,
      :changelog,
      :permissions,
      :mcp_tools,
      :artifact_url,
      :artifact_hash,
      :artifact_size,
      :published_by
    ])
    |> validate_required([:agent_id, :workspace_id, :version, :manifest])
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+/)
    |> unique_constraint([:agent_id, :version])
  end
end
