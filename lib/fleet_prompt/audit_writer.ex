defmodule FleetPrompt.AuditWriter do
  @moduledoc """
  Writes audit events for all registry operations.
  Append-only — audit events are never updated or deleted.

  In Phase 4, this will be converted to a Broadway pipeline
  for batched writes. For now, direct Repo inserts.
  """

  alias FleetPrompt.Repo
  alias FleetPrompt.Audit.Event

  @doc """
  Write an audit event.

  ## Examples

      AuditWriter.write(%{
        workspace_id: workspace_id,
        actor_user_id: user_id,
        action: "publish",
        target_type: "manifest",
        target_id: manifest_id,
        metadata: %{"version" => "2.1.0"}
      })
  """
  def write(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Write a publish audit event."
  def record_publish(manifest, actor_id) do
    write(%{
      workspace_id: get_workspace_id(manifest),
      actor_user_id: actor_id,
      action: "publish",
      target_type: "manifest",
      target_id: manifest.id,
      metadata: %{"version" => manifest.version, "agent_id" => manifest.agent_id}
    })
  end

  @doc "Write an install audit event."
  def record_install(install, actor_id) do
    write(%{
      workspace_id: install.workspace_id,
      actor_user_id: actor_id,
      action: "install",
      target_type: "install",
      target_id: install.id,
      metadata: %{"agent_id" => install.agent_id, "version_id" => install.version_id}
    })
  end

  @doc "Write a fork audit event."
  def record_fork(forked_manifest, source_id, actor_id) do
    write(%{
      workspace_id: get_workspace_id(forked_manifest),
      actor_user_id: actor_id,
      action: "fork",
      target_type: "manifest",
      target_id: forked_manifest.id,
      metadata: %{"forked_from" => source_id}
    })
  end

  @doc "Write a trust change audit event."
  def record_trust_change(agent_id, workspace_id, old_score, new_score) do
    write(%{
      workspace_id: workspace_id,
      action: "trust_change",
      target_type: "agent",
      target_id: agent_id,
      metadata: %{"old_score" => old_score, "new_score" => new_score}
    })
  end

  defp get_workspace_id(manifest) do
    case FleetPrompt.Repo.get(FleetPrompt.Agents.Agent, manifest.agent_id) do
      nil -> nil
      agent -> agent.workspace_id
    end
  end
end
