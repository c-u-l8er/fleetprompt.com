defmodule FleetPromptWeb.Router do
  use FleetPromptWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {FleetPromptWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FleetPromptWeb do
    pipe_through :browser

    live "/", SearchLive, :index
    live "/agents/:id", AgentDetailLive, :show
    live "/publishers", PublisherLive, :index
    live "/publishers/:id", PublisherLive, :show
    live "/trust", TrustDashboardLive, :index
  end

  scope "/api", FleetPromptWeb do
    pipe_through :api

    get "/health", ApiController, :health

    # Search
    get "/agents/search", ApiController, :search

    # Agent CRUD
    get "/agents/:id", ApiController, :show_agent
    get "/agents/:id/manifests", ApiController, :list_manifests
    get "/agents/:id/manifests/:version", ApiController, :show_manifest

    # Pipeline intake (CloudEvents from Agentelic)
    post "/pipeline/intake", WebhookController, :intake
  end
end
