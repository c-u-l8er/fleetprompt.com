defmodule FleetPrompt.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "fleet"

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :parent_id, :binary_id
    field :sort_order, :integer, default: 0

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :parent_id, :sort_order])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end
end
