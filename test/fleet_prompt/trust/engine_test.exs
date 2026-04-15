defmodule FleetPrompt.Trust.EngineTest do
  use ExUnit.Case, async: true

  alias FleetPrompt.Trust.Engine

  @full_input %{
    test_results: %{passed: 95, failed: 5, skipped: 0},
    spec_hash_valid: true,
    spec_sections_complete: 0.8,
    total_installs: 200,
    active_installs: 150,
    install_success_rate: 0.95,
    avg_uptime: 0.99,
    audit_events_count: 60,
    provenance_complete: true,
    permissions_minimal: true
  }

  describe "compute/1" do
    test "computes a high trust score for a well-tested, widely-used agent" do
      score = Engine.compute(@full_input)
      assert score >= 80
      assert score <= 100
    end

    test "computes zero for a completely empty agent" do
      input = %{
        test_results: %{passed: 0, failed: 0, skipped: 0},
        spec_hash_valid: false,
        spec_sections_complete: 0.0,
        total_installs: 0,
        active_installs: 0,
        install_success_rate: 0.0,
        avg_uptime: 0.0,
        audit_events_count: 0,
        provenance_complete: false,
        permissions_minimal: false
      }

      assert Engine.compute(input) == 0
    end

    test "computes a perfect 100 score" do
      input = %{
        test_results: %{passed: 100, failed: 0, skipped: 0},
        spec_hash_valid: true,
        spec_sections_complete: 1.0,
        total_installs: 100,
        active_installs: 100,
        install_success_rate: 1.0,
        avg_uptime: 1.0,
        audit_events_count: 50,
        provenance_complete: true,
        permissions_minimal: true
      }

      assert Engine.compute(input) == 100
    end

    test "test_coverage contributes 30% weight" do
      # 100% tests, nothing else
      input = %{
        test_results: %{passed: 100, failed: 0, skipped: 0},
        spec_hash_valid: false,
        spec_sections_complete: 0.0,
        total_installs: 0,
        active_installs: 0,
        install_success_rate: 0.0,
        avg_uptime: 0.0,
        audit_events_count: 0,
        provenance_complete: false,
        permissions_minimal: false
      }

      # 100 * 0.30 = 30
      assert Engine.compute(input) == 30
    end

    test "spec_compliance contributes 25% weight" do
      input = %{
        test_results: %{passed: 0, failed: 0, skipped: 0},
        spec_hash_valid: true,
        spec_sections_complete: 1.0,
        total_installs: 0,
        active_installs: 0,
        install_success_rate: 0.0,
        avg_uptime: 0.0,
        audit_events_count: 0,
        provenance_complete: false,
        permissions_minimal: false
      }

      # (50 + 1.0 * 50) * 0.25 = 25
      assert Engine.compute(input) == 25
    end

    test "usage_history contributes 25% weight" do
      input = %{
        test_results: %{passed: 0, failed: 0, skipped: 0},
        spec_hash_valid: false,
        spec_sections_complete: 0.0,
        total_installs: 100,
        active_installs: 100,
        install_success_rate: 1.0,
        avg_uptime: 1.0,
        audit_events_count: 0,
        provenance_complete: false,
        permissions_minimal: false
      }

      # (25 + 25 + 25 + 25) * 0.25 = 25
      assert Engine.compute(input) == 25
    end

    test "audit_quality contributes 20% weight" do
      input = %{
        test_results: %{passed: 0, failed: 0, skipped: 0},
        spec_hash_valid: false,
        spec_sections_complete: 0.0,
        total_installs: 0,
        active_installs: 0,
        install_success_rate: 0.0,
        avg_uptime: 0.0,
        audit_events_count: 50,
        provenance_complete: true,
        permissions_minimal: true
      }

      # (34 + 33 + 33) * 0.20 = 20
      assert Engine.compute(input) == 20
    end

    test "score is clamped to 0-100" do
      # Even with negative inputs (shouldn't happen), result stays >= 0
      input = %{
        test_results: %{passed: 0, failed: 0, skipped: 0},
        spec_hash_valid: false,
        spec_sections_complete: 0.0,
        total_installs: 0,
        active_installs: 0,
        install_success_rate: 0.0,
        avg_uptime: 0.0,
        audit_events_count: 0,
        provenance_complete: false,
        permissions_minimal: false
      }

      score = Engine.compute(input)
      assert score >= 0
      assert score <= 100
    end

    test "failed tests reduce score" do
      all_passing = %{@full_input | test_results: %{passed: 100, failed: 0, skipped: 0}}
      half_failing = %{@full_input | test_results: %{passed: 50, failed: 50, skipped: 0}}

      assert Engine.compute(all_passing) > Engine.compute(half_failing)
    end
  end

  describe "breakdown/1" do
    test "returns individual signal scores" do
      result = Engine.breakdown(@full_input)

      assert is_float(result.test_coverage)
      assert is_float(result.spec_compliance)
      assert is_float(result.usage_history)
      assert is_float(result.audit_quality)
      assert is_integer(result.overall)
      assert result.overall == Engine.compute(@full_input)
    end
  end

  describe "display/1" do
    test "returns Excellent for 90-100" do
      assert %{label: "Excellent", color: "green"} = Engine.display(95)
      assert %{label: "Excellent", color: "green"} = Engine.display(100)
      assert %{label: "Excellent", color: "green"} = Engine.display(90)
    end

    test "returns Good for 70-89" do
      assert %{label: "Good", color: "blue"} = Engine.display(85)
      assert %{label: "Good", color: "blue"} = Engine.display(70)
    end

    test "returns Fair for 50-69" do
      assert %{label: "Fair", color: "yellow"} = Engine.display(55)
    end

    test "returns Low for 25-49" do
      assert %{label: "Low", color: "orange"} = Engine.display(30)
    end

    test "returns Unverified for 0-24" do
      assert %{label: "Unverified", color: "red"} = Engine.display(10)
      assert %{label: "Unverified", color: "red"} = Engine.display(0)
    end
  end
end
