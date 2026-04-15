defmodule FleetPrompt.Trust.Supervisor do
  @moduledoc """
  DynamicSupervisor managing TrustWorker processes.
  One TrustWorker per published agent.
  """

  use DynamicSupervisor

  alias FleetPrompt.Trust.Worker

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end

  @doc "Start a TrustWorker for the given agent_id."
  def start_worker(agent_id) do
    DynamicSupervisor.start_child(__MODULE__, {Worker, agent_id})
  end

  @doc "Stop the TrustWorker for the given agent_id."
  def stop_worker(agent_id) do
    case Registry.lookup(FleetPrompt.Trust.Registry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  @doc "Ensure a TrustWorker is running for the given agent_id."
  def ensure_worker(agent_id) do
    case Registry.lookup(FleetPrompt.Trust.Registry, agent_id) do
      [{_pid, _}] -> :ok
      [] -> start_worker(agent_id) |> normalize_result()
    end
  end

  @doc "List all running TrustWorker agent_ids."
  def list_workers do
    Registry.select(FleetPrompt.Trust.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  defp normalize_result({:ok, _pid}), do: :ok
  defp normalize_result(error), do: error
end
