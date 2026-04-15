defmodule FleetPromptWeb.SearchLive do
  @moduledoc """
  Real-time agent search (⌘K). Combines full-text search
  with trust score display and category filtering.
  """

  use FleetPromptWeb, :live_view

  alias FleetPrompt.Search

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:query, "")
      |> assign(:results, [])
      |> assign(:count, 0)
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")

    socket =
      if query != "" do
        results = Search.search(query, limit: 30)
        results = FleetPrompt.Repo.preload(results, [:publisher, :trust_score])

        socket
        |> assign(:query, query)
        |> assign(:results, results)
        |> assign(:count, length(results))
      else
        assign(socket, :query, query)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    socket = assign(socket, :loading, true)

    results =
      if String.trim(query) == "" do
        []
      else
        Search.search(query, limit: 30)
        |> FleetPrompt.Repo.preload([:publisher, :trust_score])
      end

    socket =
      socket
      |> assign(:query, query)
      |> assign(:results, results)
      |> assign(:count, length(results))
      |> assign(:loading, false)

    {:noreply, push_patch(socket, to: ~p"/?q=#{query}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="search-page">
      <div style="text-align: center; margin-bottom: 2rem;">
        <h1 style="font-size: 2rem; margin-bottom: 0.5rem;">Find AI Agents</h1>
        <p style="color: var(--color-text-muted);">
          Discover production-ready agents with computed trust scores
        </p>
      </div>

      <form phx-change="search" phx-submit="search" style="margin-bottom: 2rem;">
        <.search_input value={@query} placeholder="Search agents by name, capability, or domain..." />
      </form>

      <div
        :if={@query != ""}
        style="margin-bottom: 1rem; color: var(--color-text-muted); font-size: 0.875rem;"
      >
        {if @count > 0, do: "#{@count} agents found", else: "No agents found"}
      </div>

      <div class="agent-grid" style="display: grid; gap: 1rem;">
        <.agent_card :for={agent <- @results} agent={agent} />
      </div>
    </div>
    """
  end

  defp agent_card(assigns) do
    trust = if assigns.agent.trust_score, do: assigns.agent.trust_score.overall_score, else: nil

    trust_int =
      if trust, do: Decimal.to_integer(Decimal.round(Decimal.mult(trust, 10))), else: nil

    assigns = assign(assigns, :trust_int, trust_int)

    ~H"""
    <a href={~p"/agents/#{@agent.id}"} style="text-decoration: none; color: inherit;">
      <div
        style="padding: 1.25rem; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: 0.75rem; transition: border-color 0.2s; cursor: pointer;"
        onmouseover="this.style.borderColor='var(--color-accent)'"
        onmouseout="this.style.borderColor='var(--color-border)'"
      >
        <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 0.5rem;">
          <div>
            <h3 style="font-size: 1.125rem; font-weight: 600;">{@agent.name}</h3>
            <span style="color: var(--color-text-muted); font-size: 0.8125rem;">
              {if @agent.publisher, do: @agent.publisher.name, else: "Unknown publisher"}
            </span>
          </div>
          <.trust_badge score={@trust_int} />
        </div>
        <p style="color: var(--color-text-muted); font-size: 0.875rem; margin-bottom: 0.75rem;">
          {@agent.description || "No description"}
        </p>
        <div style="display: flex; gap: 0.75rem; color: var(--color-text-muted); font-size: 0.75rem;">
          <span>↓ {@agent.download_count} installs</span>
          <span>{@agent.license}</span>
        </div>
      </div>
    </a>
    """
  end
end
