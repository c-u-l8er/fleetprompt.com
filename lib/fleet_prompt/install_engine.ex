defmodule FleetPrompt.InstallEngine do
  @moduledoc """
  Orchestrates the install flow for deploying agents.

  Flow:
  1. Permission review — display all declared permissions
  2. Delegatic policy check — org-level constraints
  3. MCP dependency resolution — verify required MCP servers
  4. OpenSentience deploy — deploy manifest to runtime
  5. Graphonomous connect — initialize telespace
  6. Audit + confirm — write audit event, return install receipt

  Currently a stub — integration points will be implemented
  as the external services come online.
  """

  alias FleetPrompt.Repo
  alias FleetPrompt.Installs.Install
  alias FleetPrompt.Manifests.Manifest
  alias FleetPrompt.AuditWriter

  require Logger

  @doc """
  Start the install flow for an agent.

  Returns `{:ok, install}` on success.
  """
  def install(agent_id, version_id, opts \\ []) do
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    installed_by = Keyword.get(opts, :installed_by)

    with {:ok, _manifest} <- verify_manifest(agent_id),
         :ok <- check_permissions(opts),
         {:ok, install} <- create_install(agent_id, version_id, workspace_id, installed_by) do
      AuditWriter.record_install(install, installed_by)
      Logger.info("Installed agent #{agent_id} for workspace #{workspace_id}")
      {:ok, install}
    end
  end

  @doc """
  Uninstall an agent deployment.
  """
  def uninstall(install_id) do
    install = Repo.get!(Install, install_id)

    install
    |> Install.uninstall_changeset()
    |> Repo.update()
  end

  # -- Private -----------------------------------------------------------------

  defp verify_manifest(agent_id) do
    case FleetPrompt.Registry.get_latest_manifest(agent_id) do
      nil -> {:error, :no_published_manifest}
      %Manifest{status: :published} = m -> {:ok, m}
      _ -> {:error, :manifest_not_published}
    end
  end

  defp check_permissions(opts) do
    # TODO: Integrate with Delegatic for org-level policy checks
    if Keyword.get(opts, :accept_permissions, false) do
      :ok
    else
      {:error, :permissions_not_accepted}
    end
  end

  defp create_install(agent_id, version_id, workspace_id, installed_by) do
    %Install{}
    |> Install.changeset(%{
      agent_id: agent_id,
      version_id: version_id,
      workspace_id: workspace_id,
      installed_by: installed_by
    })
    |> Repo.insert()
  end
end
