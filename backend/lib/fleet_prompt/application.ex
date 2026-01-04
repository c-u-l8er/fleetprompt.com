defmodule FleetPrompt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        FleetPromptWeb.Telemetry,
        FleetPrompt.Repo,
        {DNSCluster, query: Application.get_env(:fleet_prompt, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FleetPrompt.PubSub},
        {Finch, name: FleetPrompt.Finch},

        # Oban for background jobs
        {Oban, Application.fetch_env!(:fleet_prompt, Oban)}
      ] ++ inertia_ssr_children() ++ [FleetPromptWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FleetPrompt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp inertia_ssr_children do
    if Application.get_env(:inertia, :ssr, false) do
      [{Inertia.SSR, path: Path.join([Application.app_dir(:fleet_prompt), "priv"])}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FleetPromptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
