defmodule FleetPrompt.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FleetPromptWeb.Telemetry,
      FleetPrompt.Repo,
      {DNSCluster, query: Application.get_env(:fleet_prompt, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FleetPrompt.PubSub},
      {Oban, Application.fetch_env!(:fleet_prompt, Oban)},
      FleetPrompt.Cache,
      {Registry, keys: :unique, name: FleetPrompt.Trust.Registry},
      FleetPrompt.Trust.Supervisor,
      FleetPromptWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: FleetPrompt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FleetPromptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
