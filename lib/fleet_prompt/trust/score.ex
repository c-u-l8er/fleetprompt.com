defmodule FleetPrompt.Trust.Score do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:agent_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "fleet.trust_scores" do
    field :overall_score, :decimal, default: Decimal.new(0)
    field :test_coverage, :decimal, default: Decimal.new(0)
    field :usage_signal, :decimal, default: Decimal.new(0)
    field :audit_signal, :decimal, default: Decimal.new(0)
    field :freshness_signal, :decimal, default: Decimal.new(0)
    field :computed_at, :utc_datetime
    field :version_id, :binary_id
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [
      :agent_id,
      :overall_score,
      :test_coverage,
      :usage_signal,
      :audit_signal,
      :freshness_signal,
      :version_id
    ])
    |> validate_required([:agent_id, :overall_score])
    |> validate_number(:overall_score,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10
    )
    |> put_change(:computed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
