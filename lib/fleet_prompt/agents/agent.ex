defmodule FleetPrompt.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "fleet"

  schema "agents" do
    belongs_to :publisher, FleetPrompt.Publishers.Publisher
    belongs_to :category, FleetPrompt.Categories.Category

    field :workspace_id, :binary_id
    field :name, :string
    field :slug, :string
    field :description, :string
    field :license, :string, default: "MIT"
    field :is_public, :boolean, default: true
    field :is_archived, :boolean, default: false
    field :specprompt_ref, :string
    field :homepage_url, :string
    field :repository_url, :string
    field :icon_url, :string
    field :download_count, :integer, default: 0
    field :created_by, :binary_id

    # Generated column — read-only
    field :search_vector, :string, load_in_query: false

    has_many :manifests, FleetPrompt.Manifests.Manifest
    has_many :versions, FleetPrompt.Versions.Version
    has_many :installs, FleetPrompt.Installs.Install
    has_one :trust_score, FleetPrompt.Trust.Score

    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :workspace_id,
      :publisher_id,
      :category_id,
      :name,
      :slug,
      :description,
      :license,
      :is_public,
      :is_archived,
      :specprompt_ref,
      :homepage_url,
      :repository_url,
      :icon_url,
      :created_by
    ])
    |> validate_required([:workspace_id, :publisher_id, :name, :slug])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> unique_constraint([:publisher_id, :slug])
  end
end
