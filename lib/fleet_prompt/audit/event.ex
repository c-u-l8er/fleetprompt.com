defmodule FleetPrompt.Audit.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fleet.audit_events" do
    field :workspace_id, :binary_id
    field :actor_user_id, :binary_id
    field :action, :string
    field :target_type, :string
    field :target_id, :binary_id
    field :metadata, :map

    # Append-only — no updated_at
    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @valid_actions ~w(publish install fork deprecate yank trust_change uninstall)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:workspace_id, :actor_user_id, :action, :target_type, :target_id, :metadata])
    |> validate_required([:workspace_id, :action])
    |> validate_inclusion(:action, @valid_actions)
  end
end
