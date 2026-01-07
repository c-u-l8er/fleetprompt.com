defmodule FleetPromptWeb.Router do
  use FleetPromptWeb, :router
  import AshAdmin.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(FleetPromptWeb.Plugs.FetchCurrentUser)
    plug(FleetPromptWeb.Plugs.FetchOrgContext)
    plug(:assign_request_path)
    plug(FleetPromptWeb.Plugs.AdminTenant)
    plug(:put_root_layout, html: {FleetPromptWeb.Layouts, :root})
    plug(:put_layout, html: {FleetPromptWeb.Layouts, :inertia})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(Inertia.Plug)
  end

  pipeline :protected do
    plug(FleetPromptWeb.Plugs.RequireAuth, redirect_to: "/login")
  end

  # Admin baseline:
  # - requires authentication
  # - allows any member to view/select their org tenant context
  pipeline :admin do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(FleetPromptWeb.Plugs.FetchCurrentUser)
    plug(FleetPromptWeb.Plugs.FetchOrgContext)
    plug(FleetPromptWeb.Plugs.RequireAuth, redirect_to: "/login")
    plug(:assign_request_path)
    plug(FleetPromptWeb.Plugs.AdminTenant)
    plug(:put_root_layout, html: {FleetPromptWeb.Layouts, :root})
    plug(:put_layout, html: {FleetPromptWeb.Layouts, :admin})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  # Admin authorization:
  # - only org roles :owner/:admin may access the actual admin UI surfaces
  pipeline :admin_org_admin do
    plug(FleetPromptWeb.Plugs.RequireOrgAdmin,
      redirect_to: "/admin/tenant",
      unauthenticated_redirect_to: "/login"
    )
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", FleetPromptWeb do
    pipe_through(:browser)

    # Public
    get("/health", HealthController, :index)
    get("/", PageController, :home)

    # Session auth
    get("/login", AuthController, :new)
    post("/login", AuthController, :create)
    delete("/logout", AuthController, :delete)

    # Registration (create org + owner user)
    get("/register", AuthController, :register_new)
    post("/register", AuthController, :register_create)
  end

  scope "/", FleetPromptWeb do
    pipe_through([:browser, :protected])

    # Org / tenant switching (membership-gated)
    post("/org/select", OrgController, :select)

    # Protected app pages
    get("/dashboard", PageController, :dashboard)

    # Forums (Phase 6) — UX scaffold (Inertia) + placeholder routes.
    #
    # These routes are safe to ship early:
    # - the controller can render mocked / placeholder payloads
    # - Phase 6 will replace the backing data with real Ash resources + Signals/Directives
    get("/forums", ForumsController, :index)
    get("/forums/new", ForumsController, :new)
    get("/forums/c/:slug", ForumsController, :category)
    get("/forums/t/:id", ForumsController, :thread)

    # Inertia pages (UI scaffold; real implementations land in Phase 2/3)
    get("/marketplace", MarketplaceController, :index)
    get("/chat", ChatController, :index)

    # Chat SSE endpoint (Phase 3 transport)
    post("/chat/message", ChatController, :send_message)
  end

  # Admin tenant selector is available to any authenticated member.
  scope "/admin", FleetPromptWeb do
    pipe_through(:admin)

    get("/tenant", AdminTenantController, :index)
    post("/tenant", AdminTenantController, :select)
  end

  # Admin UI surfaces are restricted to org roles :owner/:admin.
  scope "/admin", FleetPromptWeb do
    pipe_through([:admin, :admin_org_admin])

    # Shell page: app-style header with AshAdmin embedded (iframe)
    get("/", AdminShellController, :index)

    get("/portal", AdminPortalController, :index)
  end

  # AshAdmin (LiveView) is mounted under /admin/ui so the /admin shell can embed it in an iframe.
  #
  # NOTE: This scope intentionally has no `FleetPromptWeb` namespace.
  scope "/admin" do
    pipe_through([:admin, :admin_org_admin])

    ash_admin("/ui")
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

  defp assign_request_path(conn, _opts) do
    assign(conn, :fp_request_path, conn.request_path)
  end
end
