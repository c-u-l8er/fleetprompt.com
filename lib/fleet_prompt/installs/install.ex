defmodule FleetPrompt.Installs.Install do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "fleet"

  schema "installs" do
    belongs_to :agent, FleetPrompt.Agents.Agent
    belongs_to :version, FleetPrompt.Versions.Version, foreign_key: :version_id

    field :workspace_id, :binary_id
    field :installed_by, :binary_id
    field :uninstalled_at, :utc_datetime

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  def changeset(install, attrs) do
    install
    |> cast(attrs, [:agent_id, :version_id, :workspace_id, :installed_by])
    |> validate_required([:agent_id, :version_id, :workspace_id])
  end

  def uninstall_changeset(install) do
    install
    |> change(uninstalled_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
