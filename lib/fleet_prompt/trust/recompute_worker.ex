defmodule FleetPrompt.Trust.RecomputeWorker do
  @moduledoc """
  Oban worker that periodically recomputes trust scores for all
  published agents. Runs on the :trust queue.

  Can be triggered:
  - Periodically via Oban cron (e.g., every 15 minutes)
  - On-demand after a batch of new install/audit events
  """

  use Oban.Worker, queue: :trust, max_attempts: 3

  alias FleetPrompt.Trust.Supervisor, as: TrustSupervisor
  alias FleetPrompt.Trust.Worker, as: TrustWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{"agent_id" => agent_id} ->
        recompute_single(agent_id)

      _ ->
        recompute_all()
    end
  end

  defp recompute_single(agent_id) do
    TrustSupervisor.ensure_worker(agent_id)
    TrustWorker.recompute(agent_id)
    Logger.debug("Trust recompute triggered for agent #{agent_id}")
    :ok
  end

  defp recompute_all do
    import Ecto.Query

    agent_ids =
      FleetPrompt.Manifests.Manifest
      |> where([m], m.status == :published)
      |> select([m], m.agent_id)
      |> distinct(true)
      |> FleetPrompt.Repo.all()

    for agent_id <- agent_ids do
      TrustSupervisor.ensure_worker(agent_id)
      TrustWorker.recompute(agent_id)
    end

    Logger.info("Trust recompute completed for #{length(agent_ids)} agents")
    :ok
  end

  @doc "Enqueue a trust recompute job for a specific agent."
  def enqueue(agent_id) do
    %{agent_id: agent_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc "Enqueue a full trust recompute job."
  def enqueue_all do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
