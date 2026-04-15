defmodule FleetPrompt.Publishers.Publisher do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fleet.publishers" do
    field :workspace_id, :binary_id
    field :name, :string
    field :slug, :string
    field :description, :string
    field :website_url, :string
    field :avatar_url, :string
    field :verified, :boolean, default: false
    field :created_by, :binary_id

    has_many :agents, FleetPrompt.Agents.Agent

    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  def changeset(publisher, attrs) do
    publisher
    |> cast(attrs, [
      :workspace_id,
      :name,
      :slug,
      :description,
      :website_url,
      :avatar_url,
      :created_by
    ])
    |> validate_required([:workspace_id, :name, :slug])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> unique_constraint(:slug)
  end
end
