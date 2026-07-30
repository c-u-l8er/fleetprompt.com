defmodule FleetPrompt.PublishAuditTest do
  @moduledoc """
  A publish is only a publish if it was recorded.

  `publish_flow_test.exs` covers the pure parts of the flow — spec-hash
  validation, trust computation, the declared constraints — without a database.
  It cannot show that an audit event was written, because it never writes one.
  These tests do, against real Postgres.

  The defect they pin: `AuditWriter.record_publish/3` used to be called for its
  side effect with its result thrown away. `audit_events.workspace_id` is NOT
  NULL, so any publish that could not resolve a workspace produced a manifest
  with no provenance record and still returned `{:ok, manifest}`.
  """
  use FleetPrompt.DataCase, async: true

  alias Kiln.Audit.Event
  alias Kiln.Manifests.Manifest
  alias FleetPrompt.Registry

  defp insert_workspace! do
    slug = "ws-#{System.unique_integer([:positive])}"

    {:ok, %{rows: [[id]]}} =
      Repo.query(
        "INSERT INTO amp.workspaces (name, slug) VALUES ($1, $2) RETURNING id::text",
        [slug, slug]
      )

    id
  end

  defp attrs(overrides \\ %{}) do
    slug = "audit-#{System.unique_integer([:positive])}"

    Map.merge(
      %{
        name: slug,
        slug: slug,
        version: "1.0.0",
        description: "published by nobody in particular",
        permissions: [%{"capability" => "read", "scope" => "read", "reason" => "testing"}],
        spec_hash: "sha256:abc123",
        build_pipeline: "agentelic"
      },
      overrides
    )
  end

  defp events_for(manifest) do
    Repo.all(from e in Event, where: e.target_id == ^manifest.id)
  end

  describe "publish_manifest/2 provenance" do
    test "writes an audit event for an agentless publish" do
      workspace_id = insert_workspace!()

      assert {:ok, manifest} = Registry.publish_manifest(attrs(), workspace_id: workspace_id)

      assert [event] = events_for(manifest)
      assert event.action == "publish"
      assert event.target_type == "manifest"
      assert event.workspace_id == workspace_id
      assert event.metadata["slug"] == manifest.slug
    end

    test "refuses a publish it cannot attribute to a workspace" do
      # No agent to derive one from, and none supplied. Before, this published
      # the manifest and silently skipped the audit.
      assert {:error, :missing_workspace_id} = Registry.publish_manifest(attrs())
    end

    test "an unknown workspace rolls the manifest back" do
      a = attrs()

      assert {:error, %Ecto.Changeset{} = cs} =
               Registry.publish_manifest(a, workspace_id: Ecto.UUID.generate())

      assert [{:workspace_id, {_, opts}}] = cs.errors
      assert opts[:constraint] == :foreign

      # Nothing half-published.
      assert Repo.get_by(Manifest, slug: a.slug, version: a.version) == nil
    end
  end
end
