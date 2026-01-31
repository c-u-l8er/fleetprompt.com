defmodule FleetPromptWeb.PageController do
  use FleetPromptWeb, :controller

  # Use the shared Inertia helper with a module prefix to avoid conflicts with the
  # `render_inertia/3` imported by `use FleetPromptWeb, :controller`.

  alias FleetPrompt.Accounts.Organization
  alias FleetPrompt.Accounts.User
  alias FleetPrompt.Skills.Skill
  alias FleetPrompt.Agents.Agent

  def home(conn, _params) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Home", %{
      message: "Deploy fleets of AI agents in minutes"
    })
  end

  def dashboard(conn, _params) do
    # Tenant is optional for the app UI, but required to read tenant-scoped resources like Agents.
    tenant =
      case conn.assigns[:ash_tenant] do
        t when is_binary(t) and t != "" -> t
        _ -> nil
      end

    org_count =
      Organization
      |> Ash.Query.for_read(:read)
      |> Ash.read!()
      |> length()

    user_count =
      User
      |> Ash.Query.for_read(:read)
      |> Ash.read!()
      |> length()

    skill_count =
      Skill
      |> Ash.Query.for_read(:read)
      |> Ash.read!()
      |> length()

    agent_count =
      if tenant do
        Agent
        |> Ash.Query.for_read(:read)
        |> Ash.read!(tenant: tenant)
        |> length()
      else
        0
      end

    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Dashboard", %{
      title: "Dashboard",
      message: "Welcome to your FleetPrompt dashboard.",
      tenant: tenant,
      stats: %{
        organizations: org_count,
        users: user_count,
        skills: skill_count,
        agents: agent_count
      }
    })
  end

  def marketplace(conn, _params) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Marketplace", %{
      title: "Marketplace",
      subtitle: "Browse installable packages (agents, workflows, skills). Coming soon."
    })
  end

  def chat(conn, _params) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Chat", %{})
  end

  def profile(conn, _params) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Profile", %{
      title: "Profile",
      subtitle: "Manage your account profile. (Coming soon.)"
    })
  end

  def settings(conn, _params) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, "Settings", %{
      title: "Settings",
      subtitle: "Account and application settings. (Coming soon.)"
    })
  end
end
