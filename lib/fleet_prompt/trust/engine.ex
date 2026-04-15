defmodule FleetPrompt.Trust.Engine do
  @moduledoc """
  Computes trust scores for published agents.
  Score range: 0-100. Deterministic — no LLM calls.

  Four weighted signals:
  - test_coverage (30%): pass rate from test results
  - spec_compliance (25%): spec hash validity + section coverage
  - usage_history (25%): installs, retention, success rate, uptime
  - audit_quality (20%): audit trail depth, provenance, minimal permissions
  """

  @weights %{
    test_coverage: 0.30,
    spec_compliance: 0.25,
    usage_history: 0.25,
    audit_quality: 0.20
  }

  @type trust_input :: %{
          test_results: %{passed: number(), failed: number(), skipped: number()},
          spec_hash_valid: boolean(),
          spec_sections_complete: float(),
          total_installs: non_neg_integer(),
          active_installs: non_neg_integer(),
          install_success_rate: float(),
          avg_uptime: float(),
          audit_events_count: non_neg_integer(),
          provenance_complete: boolean(),
          permissions_minimal: boolean()
        }

  @doc """
  Compute a trust score (0-100) from the given input signals.

  ## Examples

      iex> FleetPrompt.Trust.Engine.compute(%{
      ...>   test_results: %{passed: 95, failed: 5, skipped: 0},
      ...>   spec_hash_valid: true,
      ...>   spec_sections_complete: 0.8,
      ...>   total_installs: 200,
      ...>   active_installs: 150,
      ...>   install_success_rate: 0.95,
      ...>   avg_uptime: 0.99,
      ...>   audit_events_count: 60,
      ...>   provenance_complete: true,
      ...>   permissions_minimal: true
      ...> })
      85

  """
  @spec compute(trust_input()) :: integer()
  def compute(input) do
    test_score = compute_test_score(input)
    spec_score = compute_spec_score(input)
    usage_score = compute_usage_score(input)
    audit_score = compute_audit_score(input)

    raw =
      test_score * @weights.test_coverage +
        spec_score * @weights.spec_compliance +
        usage_score * @weights.usage_history +
        audit_score * @weights.audit_quality

    raw |> round() |> max(0) |> min(100)
  end

  @doc "Returns the individual signal scores as a map."
  @spec breakdown(trust_input()) :: %{
          test_coverage: float(),
          spec_compliance: float(),
          usage_history: float(),
          audit_quality: float(),
          overall: integer()
        }
  def breakdown(input) do
    test_score = compute_test_score(input)
    spec_score = compute_spec_score(input)
    usage_score = compute_usage_score(input)
    audit_score = compute_audit_score(input)

    raw =
      test_score * @weights.test_coverage +
        spec_score * @weights.spec_compliance +
        usage_score * @weights.usage_history +
        audit_score * @weights.audit_quality

    %{
      test_coverage: Float.round(test_score, 2),
      spec_compliance: Float.round(spec_score, 2),
      usage_history: Float.round(usage_score, 2),
      audit_quality: Float.round(audit_score, 2),
      overall: raw |> round() |> max(0) |> min(100)
    }
  end

  @doc "Returns a display label and color for a trust score."
  @spec display(integer()) :: %{label: String.t(), color: String.t()}
  def display(score) when score >= 90, do: %{label: "Excellent", color: "green"}
  def display(score) when score >= 70, do: %{label: "Good", color: "blue"}
  def display(score) when score >= 50, do: %{label: "Fair", color: "yellow"}
  def display(score) when score >= 25, do: %{label: "Low", color: "orange"}
  def display(_score), do: %{label: "Unverified", color: "red"}

  # -- Signal computations -----------------------------------------------------

  defp compute_test_score(%{test_results: %{passed: p, failed: f, skipped: s}}) do
    total = p + f + s
    if total == 0, do: 0.0, else: p / total * 100
  end

  defp compute_test_score(_), do: 0.0

  defp compute_spec_score(%{spec_hash_valid: valid, spec_sections_complete: pct}) do
    base = if valid, do: 50, else: 0
    base + pct * 50
  end

  defp compute_spec_score(_), do: 0.0

  defp compute_usage_score(%{
         total_installs: total,
         active_installs: active,
         install_success_rate: rate,
         avg_uptime: uptime
       }) do
    install_signal = min(total / 100, 1.0) * 25
    retention_signal = if total > 0, do: active / total * 25, else: 0
    rate_signal = rate * 25
    uptime_signal = uptime * 25
    install_signal + retention_signal + rate_signal + uptime_signal
  end

  defp compute_usage_score(_), do: 0.0

  defp compute_audit_score(%{
         audit_events_count: count,
         provenance_complete: provenance,
         permissions_minimal: minimal
       }) do
    trail_signal = min(count / 50, 1.0) * 34
    provenance_signal = if provenance, do: 33, else: 0
    minimal_signal = if minimal, do: 33, else: 0
    trail_signal + provenance_signal + minimal_signal
  end

  defp compute_audit_score(_), do: 0.0
end
