defmodule FleetPrompt.PublishFlowTest do
  @moduledoc """
  Tests the full publish flow from BUILD.md success criteria #1:
  - Manifest publish validates spec hash
  - Enforces version immutability
  - Computes initial trust score
  """

  use ExUnit.Case, async: true

  alias FleetPrompt.Registry
  alias FleetPrompt.Trust.Engine

  @valid_attrs %{
    name: "test-agent",
    slug: "test-agent",
    version: "1.0.0",
    description: "A test agent",
    permissions: [%{"capability" => "read", "scope" => "read", "reason" => "testing"}],
    agent_id: Ecto.UUID.generate(),
    publisher_id: Ecto.UUID.generate(),
    spec_url: "https://specprompt.com/specs/test/SPEC.md",
    spec_hash: "sha256:abc123def456",
    build_pipeline: "agentelic",
    build_hash: "sha256:build123",
    test_results: %{"passed" => 95, "failed" => 5, "skipped" => 0}
  }

  describe "spec_hash validation" do
    test "publish_manifest rejects missing spec_hash" do
      attrs = Map.delete(@valid_attrs, :spec_hash)
      assert {:error, :missing_spec_hash} = Registry.publish_manifest(attrs)
    end

    test "publish_manifest rejects empty spec_hash" do
      attrs = Map.put(@valid_attrs, :spec_hash, "")
      assert {:error, :missing_spec_hash} = Registry.publish_manifest(attrs)
    end

    test "publish_manifest rejects nil spec_hash" do
      attrs = Map.put(@valid_attrs, :spec_hash, nil)
      assert {:error, :missing_spec_hash} = Registry.publish_manifest(attrs)
    end

    test "publish_manifest accepts valid spec_hash (passes validation step)" do
      # Verify that the spec validation step succeeds with a valid hash.
      # We test the internal validation by confirming that with a valid spec_hash,
      # the error is NOT :missing_spec_hash (it will be a DB error since no DB).
      attrs = @valid_attrs

      try do
        result = Registry.publish_manifest(attrs)
        # If we somehow get here, it should not be a spec validation error
        refute match?({:error, :missing_spec_hash}, result)
      rescue
        # DB connection errors are expected — the point is we passed spec validation
        DBConnection.OwnershipError -> :ok
      end
    end
  end

  describe "trust score computation on publish" do
    test "compute_and_attach_trust computes from test results" do
      # Verify the TrustEngine computes a non-zero score for our attrs
      trust_input = %{
        test_results: %{passed: 95, failed: 5, skipped: 0},
        spec_hash_valid: true,
        spec_sections_complete: 0.5,
        total_installs: 0,
        active_installs: 0,
        install_success_rate: 0.0,
        avg_uptime: 0.0,
        audit_events_count: 0,
        provenance_complete: true,
        permissions_minimal: true
      }

      score = Engine.compute(trust_input)
      # test: 95% * 100 * 0.30 = 28.5
      # spec: (50 + 0.5*50) * 0.25 = 18.75
      # usage: 0
      # audit: (0 + 0 + 33) * 0.20 = 6.6
      # total ≈ 54
      assert score > 0
      assert score <= 100
    end

    test "zero test results produce lower trust" do
      zero_tests = %{
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

      assert Engine.compute(zero_tests) == 0
    end
  end

  describe "version immutability" do
    test "manifest changeset declares unique constraint on agent_id + version" do
      changeset =
        FleetPrompt.Manifests.Manifest.changeset(%FleetPrompt.Manifests.Manifest{}, @valid_attrs)

      assert changeset.valid?

      # The unique constraint is enforced at DB level via:
      # unique_constraint([:agent_id, :version], name: "manifests_agent_id_version_key")
      # The name matches the real Postgres constraint (which follows
      # the `<table>_<cols>_key` convention, not the Ecto-default
      # `_index` suffix).
      assert Enum.any?(changeset.constraints, fn c ->
               c.type == :unique and
                 c.constraint == "manifests_agent_id_version_key"
             end)
    end
  end
end
