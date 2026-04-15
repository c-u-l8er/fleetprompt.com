defmodule FleetPromptWeb.TrustDashboardLive do
  @moduledoc """
  Trust score dashboard showing all agents with their computed
  trust scores, organized by trust tier.
  """

  use FleetPromptWeb, :live_view

  alias FleetPrompt.Trust.Engine

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FleetPrompt.PubSub, "trust:scores")
    end

    agents = load_agents_with_trust()

    socket =
      socket
      |> assign(:agents, agents)
      |> assign(:tier_filter, "all")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"tier" => tier}, socket) do
    {:noreply, assign(socket, :tier_filter, tier)}
  end

  @impl true
  def handle_info({:trust_updated, _agent_id, _score, _at}, socket) do
    # Refresh the list when any trust score updates
    {:noreply, assign(socket, :agents, load_agents_with_trust())}
  end

  @impl true
  def render(assigns) do
    filtered =
      if assigns.tier_filter == "all" do
        assigns.agents
      else
        Enum.filter(assigns.agents, fn a ->
          display = trust_display(a)
          String.downcase(display.label) == assigns.tier_filter
        end)
      end

    assigns = assign(assigns, :filtered_agents, filtered)

    ~H"""
    <div class="trust-dashboard">
      <h1 style="font-size: 2rem; margin-bottom: 0.5rem;">Trust Dashboard</h1>
      <p style="color: var(--color-text-muted); margin-bottom: 2rem;">
        Trust scores are computed from test coverage, spec compliance, usage, and audit quality.
      </p>

      <%!-- Tier filters --%>
      <div style="display: flex; gap: 0.5rem; margin-bottom: 2rem; flex-wrap: wrap;">
        <.tier_button tier="all" active={@tier_filter} label="All" />
        <.tier_button tier="excellent" active={@tier_filter} label="Excellent (90-100)" />
        <.tier_button tier="good" active={@tier_filter} label="Good (70-89)" />
        <.tier_button tier="fair" active={@tier_filter} label="Fair (50-69)" />
        <.tier_button tier="low" active={@tier_filter} label="Low (25-49)" />
        <.tier_button tier="unverified" active={@tier_filter} label="Unverified (0-24)" />
      </div>

      <%!-- Agent list --%>
      <div
        :if={@filtered_agents == []}
        style="color: var(--color-text-muted); padding: 2rem 0; text-align: center;"
      >
        No agents in this tier.
      </div>

      <table :if={@filtered_agents != []} style="width: 100%; border-collapse: collapse;">
        <thead>
          <tr style="border-bottom: 1px solid var(--color-border);">
            <th style="text-align: left; padding: 0.75rem 0; color: var(--color-text-muted); font-size: 0.75rem; font-weight: 500; text-transform: uppercase;">
              Agent
            </th>
            <th style="text-align: left; padding: 0.75rem 0; color: var(--color-text-muted); font-size: 0.75rem; font-weight: 500; text-transform: uppercase;">
              Publisher
            </th>
            <th style="text-align: right; padding: 0.75rem 0; color: var(--color-text-muted); font-size: 0.75rem; font-weight: 500; text-transform: uppercase;">
              Trust Score
            </th>
            <th style="text-align: right; padding: 0.75rem 0; color: var(--color-text-muted); font-size: 0.75rem; font-weight: 500; text-transform: uppercase;">
              Installs
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={agent <- @filtered_agents} style="border-bottom: 1px solid var(--color-border);">
            <td style="padding: 0.75rem 0;">
              <a
                href={~p"/agents/#{agent.id}"}
                style="color: var(--color-text); text-decoration: none; font-weight: 500;"
              >
                {agent.name}
              </a>
            </td>
            <td style="padding: 0.75rem 0; color: var(--color-text-muted);">
              {if agent.publisher, do: agent.publisher.name, else: "—"}
            </td>
            <td style="padding: 0.75rem 0; text-align: right;">
              <.trust_badge score={trust_score_int(agent)} />
            </td>
            <td style="padding: 0.75rem 0; text-align: right; color: var(--color-text-muted);">
              {agent.download_count}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp tier_button(assigns) do
    active_style =
      if assigns.tier == assigns.active,
        do: "background: var(--color-accent); color: white;",
        else: "background: var(--color-surface); color: var(--color-text-muted);"

    assigns = assign(assigns, :style, active_style)

    ~H"""
    <button
      phx-click="filter"
      phx-value-tier={@tier}
      style={"border: 1px solid var(--color-border); padding: 0.375rem 0.875rem; border-radius: 9999px; font-size: 0.8125rem; cursor: pointer; #{@style}"}
    >
      {@label}
    </button>
    """
  end

  defp load_agents_with_trust do
    import Ecto.Query

    FleetPrompt.Agents.Agent
    |> where([a], a.is_public == true)
    |> order_by([a], desc: a.download_count)
    |> limit(100)
    |> FleetPrompt.Repo.all()
    |> FleetPrompt.Repo.preload([:publisher, :trust_score])
  end

  defp trust_display(agent) do
    score = trust_score_int(agent)
    if score, do: Engine.display(score), else: %{label: "N/A", color: "gray"}
  end

  defp trust_score_int(agent) do
    case agent.trust_score do
      nil -> nil
      ts -> Decimal.to_integer(Decimal.round(Decimal.mult(ts.overall_score, 10)))
    end
  end
end
