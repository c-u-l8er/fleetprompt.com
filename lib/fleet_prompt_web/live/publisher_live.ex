defmodule FleetPromptWeb.PublisherLive do
  @moduledoc """
  Publisher profile page showing published agents and verification status.
  Index shows all publishers; show displays a single publisher's profile.
  """

  use FleetPromptWeb, :live_view

  alias FleetPrompt.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    publishers = load_publishers()

    socket
    |> assign(:page_title, "Publishers")
    |> assign(:publishers, publishers)
    |> assign(:publisher, nil)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    publisher =
      Repo.get(FleetPrompt.Publishers.Publisher, id)
      |> Repo.preload(agents: [:trust_score])

    if publisher do
      socket
      |> assign(:page_title, publisher.name)
      |> assign(:publisher, publisher)
      |> assign(:publishers, [])
    else
      push_navigate(socket, to: ~p"/publishers")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="publisher-page">
      <%!-- Index view --%>
      <div :if={@live_action == :index}>
        <h1 style="font-size: 2rem; margin-bottom: 0.5rem;">Publishers</h1>
        <p style="color: var(--color-text-muted); margin-bottom: 2rem;">
          Organizations and individuals publishing agents on FleetPrompt.
        </p>

        <div style="display: grid; gap: 1rem; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));">
          <a
            :for={pub <- @publishers}
            href={~p"/publishers/#{pub.id}"}
            style="text-decoration: none; color: inherit;"
          >
            <div style="padding: 1.25rem; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: 0.75rem;">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
                <h3 style="font-size: 1.125rem; font-weight: 600;">{pub.name}</h3>
                <span :if={pub.verified} style="color: var(--color-green); font-size: 0.875rem;">
                  ✓ Verified
                </span>
              </div>
              <p
                :if={pub.description}
                style="color: var(--color-text-muted); font-size: 0.875rem; margin-bottom: 0.5rem;"
              >
                {pub.description}
              </p>
              <span style="color: var(--color-text-muted); font-size: 0.75rem;">
                @{pub.slug}
              </span>
            </div>
          </a>
        </div>

        <div
          :if={@publishers == []}
          style="color: var(--color-text-muted); padding: 2rem 0; text-align: center;"
        >
          No publishers registered yet.
        </div>
      </div>

      <%!-- Show view --%>
      <div :if={@live_action == :show && @publisher}>
        <div style="margin-bottom: 2rem;">
          <a
            href={~p"/publishers"}
            style="color: var(--color-text-muted); text-decoration: none; font-size: 0.875rem;"
          >
            ← Back to publishers
          </a>
        </div>

        <div style="margin-bottom: 2rem;">
          <div style="display: flex; align-items: center; gap: 1rem; margin-bottom: 0.5rem;">
            <h1 style="font-size: 2rem;">{@publisher.name}</h1>
            <span
              :if={@publisher.verified}
              style="padding: 0.25rem 0.625rem; background: #052e16; color: var(--color-green); border-radius: 9999px; font-size: 0.75rem; font-weight: 600;"
            >
              ✓ Verified
            </span>
          </div>
          <p style="color: var(--color-text-muted);">@{@publisher.slug}</p>
          <p :if={@publisher.description} style="margin-top: 0.5rem;">{@publisher.description}</p>
          <a
            :if={@publisher.website_url}
            href={@publisher.website_url}
            target="_blank"
            style="color: var(--color-accent); font-size: 0.875rem; text-decoration: none;"
          >
            {URI.parse(@publisher.website_url).host || @publisher.website_url}
          </a>
        </div>

        <h2 style="font-size: 1.25rem; margin-bottom: 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid var(--color-border);">
          Published Agents ({length(@publisher.agents)})
        </h2>

        <div style="display: grid; gap: 1rem;">
          <a
            :for={agent <- @publisher.agents}
            href={~p"/agents/#{agent.id}"}
            style="text-decoration: none; color: inherit;"
          >
            <div style="padding: 1rem; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: 0.5rem; display: flex; justify-content: space-between; align-items: center;">
              <div>
                <span style="font-weight: 600;">{agent.name}</span>
                <span style="color: var(--color-text-muted); margin-left: 0.5rem; font-size: 0.875rem;">
                  {agent.description}
                </span>
              </div>
              <div style="display: flex; gap: 0.75rem; align-items: center;">
                <.trust_badge score={agent_trust_score(agent)} />
                <span style="color: var(--color-text-muted); font-size: 0.8125rem;">
                  ↓ {agent.download_count}
                </span>
              </div>
            </div>
          </a>
        </div>

        <div
          :if={@publisher.agents == []}
          style="color: var(--color-text-muted); padding: 2rem 0; text-align: center;"
        >
          No agents published yet.
        </div>
      </div>
    </div>
    """
  end

  defp load_publishers do
    import Ecto.Query

    FleetPrompt.Publishers.Publisher
    |> order_by([p], desc: p.verified, asc: p.name)
    |> Repo.all()
  end

  defp agent_trust_score(agent) do
    case agent.trust_score do
      nil -> nil
      ts -> Decimal.to_integer(Decimal.round(Decimal.mult(ts.overall_score, 10)))
    end
  end
end
