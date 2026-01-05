defmodule FleetPromptWeb.PageController do
  use FleetPromptWeb, :controller

  def home(conn, _params) do
    render_inertia(conn, "Home", %{
      message: "Deploy AI agent fleets in minutes"
    })
  end

  def dashboard(conn, _params) do
    render_inertia(conn, "Dashboard", %{
      title: "Dashboard",
      message: "Welcome to your FleetPrompt dashboard."
    })
  end

  def marketplace(conn, _params) do
    render_inertia(conn, "Marketplace", %{
      title: "Marketplace",
      subtitle: "Browse installable packages (agents, workflows, skills). Coming soon."
    })
  end

  def chat(conn, _params) do
    render_inertia(conn, "Chat", %{})
  end
end
