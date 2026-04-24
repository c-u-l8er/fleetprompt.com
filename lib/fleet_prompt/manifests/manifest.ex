defmodule FleetPrompt.Manifests.Manifest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "fleet"

  schema "manifests" do
    belongs_to :agent, FleetPrompt.Agents.Agent
    belongs_to :publisher, FleetPrompt.Publishers.Publisher

    # Identity
    field :name, :string
    field :slug, :string
    field :version, :string
    field :description, :string
    field :category, :string
    field :tags, {:array, :string}, default: []

    # Spec linkage
    field :spec_url, :string
    field :spec_hash, :string

    # Permissions (declared upfront)
    # Each: %{capability: "orders:read", scope: "read", reason: "..."}
    field :permissions, {:array, :map}, default: []

    # MCP dependencies
    # Each: %{name: "graphonomous", url: "...", required: true}
    field :mcp_servers, {:array, :map}, default: []

    # Runtime requirements
    field :runtime, :string, default: "opensentience"
    field :min_runtime_version, :string

    # Build provenance
    field :build_pipeline, :string
    field :build_hash, :string
    field :test_results, :map, default: %{}

    # Trust (computed, not declared)
    field :trust_score, :integer

    # Lifecycle
    field :status, Ecto.Enum,
      values: [:draft, :published, :deprecated, :yanked],
      default: :draft

    field :deprecated_reason, :string
    field :forked_from, :binary_id

    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  @required_fields [:name, :slug, :version, :description, :permissions, :agent_id, :publisher_id]
  @optional_fields [
    :category,
    :tags,
    :spec_url,
    :spec_hash,
    :mcp_servers,
    :runtime,
    :min_runtime_version,
    :build_pipeline,
    :build_hash,
    :test_results,
    :status,
    :deprecated_reason,
    :forked_from
  ]

  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$/)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_inclusion(:build_pipeline, ~w(agentelic manual ci))
    |> validate_number(:trust_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    # DB-level constraint is named `manifests_agent_id_version_key`
    # (Postgres's default for UNIQUE). Previously declared as
    # `fleet.manifests_agent_id_version_index` which never matched —
    # the Ecto `changeset_errors` path for duplicate-version publishes
    # would silently fall through to a raised constraint error instead
    # of becoming a `{:error, changeset}` tuple.
    |> unique_constraint([:agent_id, :version],
      name: "manifests_agent_id_version_key"
    )
  end

  @doc """
  Changeset for status transitions only. Enforces valid transitions:
  - draft → published
  - published → deprecated | yanked
  - deprecated → yanked
  """
  def status_changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [:status, :deprecated_reason])
    |> validate_required([:status])
    |> validate_status_transition(manifest.status)
  end

  defp validate_status_transition(changeset, current_status) do
    case get_change(changeset, :status) do
      nil ->
        changeset

      new_status ->
        if valid_transition?(current_status, new_status) do
          changeset
        else
          add_error(
            changeset,
            :status,
            "invalid transition from #{current_status} to #{new_status}"
          )
        end
    end
  end

  defp valid_transition?(:draft, :published), do: true
  defp valid_transition?(:published, :deprecated), do: true
  defp valid_transition?(:published, :yanked), do: true
  defp valid_transition?(:deprecated, :yanked), do: true
  defp valid_transition?(_, _), do: false
end
