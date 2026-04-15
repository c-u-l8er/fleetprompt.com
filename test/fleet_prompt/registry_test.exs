defmodule FleetPrompt.RegistryTest do
  use FleetPrompt.DataCase, async: true

  alias FleetPrompt.Manifests.Manifest

  defp valid_manifest_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "customer-support",
        slug: "customer-support",
        version: "1.0.0",
        description: "AI customer support agent",
        permissions: [
          %{
            "capability" => "tickets:read",
            "scope" => "read",
            "reason" => "Read support tickets"
          }
        ],
        runtime: "opensentience",
        build_pipeline: "agentelic",
        test_results: %{"passed" => 42, "failed" => 0, "skipped" => 1},
        agent_id: Ecto.UUID.generate(),
        publisher_id: Ecto.UUID.generate()
      },
      overrides
    )
  end

  describe "manifest changeset" do
    test "valid manifest changeset" do
      changeset = Manifest.changeset(%Manifest{}, valid_manifest_attrs())
      assert changeset.valid?
    end

    test "rejects invalid semver" do
      changeset =
        Manifest.changeset(%Manifest{}, valid_manifest_attrs(%{version: "not-a-version"}))

      refute changeset.valid?
      assert %{version: _} = errors_on(changeset)
    end

    test "rejects invalid slug" do
      changeset = Manifest.changeset(%Manifest{}, valid_manifest_attrs(%{slug: "Invalid Slug!"}))
      refute changeset.valid?
      assert %{slug: _} = errors_on(changeset)
    end

    test "rejects missing required fields" do
      changeset = Manifest.changeset(%Manifest{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert %{name: _, slug: _, version: _, description: _} = errors
    end

    test "accepts semver with prerelease" do
      changeset =
        Manifest.changeset(%Manifest{}, valid_manifest_attrs(%{version: "1.0.0-beta.1"}))

      assert changeset.valid?
    end
  end

  describe "status transitions" do
    test "draft → published is valid" do
      manifest = %Manifest{status: :draft}
      changeset = Manifest.status_changeset(manifest, %{status: :published})
      assert changeset.valid?
    end

    test "published → deprecated is valid" do
      manifest = %Manifest{status: :published}

      changeset =
        Manifest.status_changeset(manifest, %{
          status: :deprecated,
          deprecated_reason: "Superseded by v2"
        })

      assert changeset.valid?
    end

    test "published → yanked is valid" do
      manifest = %Manifest{status: :published}
      changeset = Manifest.status_changeset(manifest, %{status: :yanked})
      assert changeset.valid?
    end

    test "deprecated → yanked is valid" do
      manifest = %Manifest{status: :deprecated}
      changeset = Manifest.status_changeset(manifest, %{status: :yanked})
      assert changeset.valid?
    end

    test "draft → deprecated is invalid" do
      manifest = %Manifest{status: :draft}
      changeset = Manifest.status_changeset(manifest, %{status: :deprecated})
      refute changeset.valid?
      assert %{status: ["invalid transition from draft to deprecated"]} = errors_on(changeset)
    end

    test "yanked → published is invalid" do
      manifest = %Manifest{status: :yanked}
      changeset = Manifest.status_changeset(manifest, %{status: :published})
      refute changeset.valid?
    end

    test "draft → yanked is invalid" do
      manifest = %Manifest{status: :draft}
      changeset = Manifest.status_changeset(manifest, %{status: :yanked})
      refute changeset.valid?
    end
  end
end
