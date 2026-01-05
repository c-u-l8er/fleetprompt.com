defmodule FleetPromptWeb.Router do
  use FleetPromptWeb, :router
  import AshAdmin.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(FleetPromptWeb.Plugs.AdminTenant)
    plug(:put_root_layout, html: {FleetPromptWeb.Layouts, :root})
    plug(:put_layout, html: {FleetPromptWeb.Layouts, :inertia})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(Inertia.Plug)
  end

  pipeline :admin do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(FleetPromptWeb.Plugs.AdminTenant)
    plug(:put_root_layout, html: {FleetPromptWeb.Layouts, :root})
    plug(:put_layout, html: {FleetPromptWeb.Layouts, :admin})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", FleetPromptWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/dashboard", PageController, :dashboard)

    # Inertia pages (UI scaffold; real implementations land in Phase 2/3)
    get("/marketplace", MarketplaceController, :index)
    get("/chat", ChatController, :index)

    # Chat SSE endpoint (Phase 3 transport)
    post("/chat/message", ChatController, :send_message)
  end

  # Admin utilities (regular controllers) stay in the FleetPromptWeb namespace
  scope "/admin", FleetPromptWeb do
    pipe_through(:admin)

    get("/portal", AdminPortalController, :index)
    get("/tenant", AdminTenantController, :index)
    post("/tenant", AdminTenantController, :select)
  end

  # AshAdmin (LiveView) should not be namespaced under FleetPromptWeb to avoid
  # module resolution/verification warnings during compilation.
  scope "/admin" do
    pipe_through(:admin)

    ash_admin("/",
      domains: [
        FleetPrompt.Accounts,
        FleetPrompt.Agents,
        FleetPrompt.Skills,
        FleetPrompt.Packages
      ]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", FleetPromptWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fleet_prompt, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: FleetPromptWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
