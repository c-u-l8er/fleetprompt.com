defmodule FleetPrompt.AuditWriter do
  @moduledoc """
  Audit events for *marketplace* operations.

  Manifest provenance — publish and fork — belongs to the engine and lives in
  `Kiln.AuditWriter`. What is left here is the half KILN deliberately does not
  have: installs. An install is a marketplace act against a listing, and the
  ship half of the dark factory has not been extracted — `installs.agent_id`
  and `agent_versions.agent_id` carry hard foreign keys into `fleet.agents`, so
  extracting them means deciding what an install is an install *of*.

  Both halves write to the same append-only `fleet.audit_events` table through
  `Kiln.AuditWriter.write/1`, so there is one insert path and one changeset
  rather than two that can drift.

  `record_trust_change/4` used to live here and had no caller in either repo.
  Trust is a computed marketplace signal, so if it comes back it comes back
  with something that reads it.
  """

  @doc """
  Write an install audit event.

  `workspace_id` comes off the install itself, which has one because an install
  happens somewhere. Publish had to be handed one explicitly, and finding out
  that it wasn't is what surfaced the missing-provenance defect.
  """
  def record_install(install, actor_id) do
    Kiln.AuditWriter.write(%{
      workspace_id: install.workspace_id,
      actor_user_id: actor_id,
      action: "install",
      target_type: "install",
      target_id: install.id,
      metadata: %{"agent_id" => install.agent_id, "version_id" => install.version_id}
    })
  end
end
