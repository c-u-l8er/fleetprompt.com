defmodule FleetPromptWeb.PageController do
  use FleetPromptWeb, :controller

  def home(conn, _params) do
    render_inertia(conn, "Home", %{
      message: "Deploy AI agent fleets in minutes"
    })
  end
end
