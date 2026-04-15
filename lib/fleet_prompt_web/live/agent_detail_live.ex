defmodule FleetPromptWeb.AgentDetailLive do
  @moduledoc """
  Agent detail page showing manifest, permissions, trust breakdown,
  version history, and fork button.
  """

  use FleetPromptWeb, :live_view

  alias FleetPrompt.Registry
  alias FleetPrompt.Trust.Engine

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agent = Registry.get_agent(id)

    case agent do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/")}

      agent ->
        agent = FleetPrompt.Repo.preload(agent, [:publisher, :trust_score, :manifests])
        latest = Registry.get_latest_manifest(id)
        manifests = Registry.list_manifests(id)

        trust_breakdown =
          if latest && latest.trust_score do
            Engine.display(latest.trust_score)
          else
            %{label: "N/A", color: "gray"}
          end

        socket =
          socket
          |> assign(:agent, agent)
          |> assign(:latest, latest)
          |> assign(:manifests, manifests)
          |> assign(:trust_display, trust_breakdown)

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-detail">
      <div style="margin-bottom: 2rem;">
        <a
          href={~p"/"}
          style="color: var(--color-text-muted); text-decoration: none; font-size: 0.875rem;"
        >
          ← Back to search
        </a>
      </div>

      <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 2rem;">
        <div>
          <h1 style="font-size: 2rem; margin-bottom: 0.25rem;">{@agent.name}</h1>
          <p style="color: var(--color-text-muted);">
            by {if @agent.publisher, do: @agent.publisher.name, else: "Unknown"} · {@agent.license} · ↓ {@agent.download_count} installs
          </p>
        </div>
        <div style="display: flex; gap: 0.75rem; align-items: center;">
          <.trust_badge score={if @latest, do: @latest.trust_score} />
          <.status_pill :if={@latest} status={@latest.status} />
        </div>
      </div>

      <p :if={@agent.description} style="font-size: 1.0625rem; margin-bottom: 2rem; line-height: 1.7;">
        {@agent.description}
      </p>

      <%!-- Latest Manifest --%>
      <section :if={@latest} style="margin-bottom: 2.5rem;">
        <h2 style="font-size: 1.25rem; margin-bottom: 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid var(--color-border);">
          Latest: v{@latest.version}
        </h2>

        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1.5rem;">
          <div style="padding: 1rem; background: var(--color-surface); border-radius: 0.5rem;">
            <div style="color: var(--color-text-muted); font-size: 0.75rem; margin-bottom: 0.25rem;">
              Runtime
            </div>
            <div style="font-weight: 600;">{@latest.runtime || "opensentience"}</div>
          </div>
          <div style="padding: 1rem; background: var(--color-surface); border-radius: 0.5rem;">
            <div style="color: var(--color-text-muted); font-size: 0.75rem; margin-bottom: 0.25rem;">
              Build Pipeline
            </div>
            <div style="font-weight: 600;">{@latest.build_pipeline || "manual"}</div>
          </div>
          <div style="padding: 1rem; background: var(--color-surface); border-radius: 0.5rem;">
            <div style="color: var(--color-text-muted); font-size: 0.75rem; margin-bottom: 0.25rem;">
              Category
            </div>
            <div style="font-weight: 600;">{@latest.category || "uncategorized"}</div>
          </div>
          <div
            :if={@latest.spec_url}
            style="padding: 1rem; background: var(--color-surface); border-radius: 0.5rem;"
          >
            <div style="color: var(--color-text-muted); font-size: 0.75rem; margin-bottom: 0.25rem;">
              Spec
            </div>
            <div style="font-weight: 600; font-size: 0.875rem; word-break: break-all;">
              {@latest.spec_url}
            </div>
          </div>
        </div>

        <%!-- Permissions --%>
        <div :if={@latest.permissions != []} style="margin-bottom: 1.5rem;">
          <h3 style="font-size: 1rem; margin-bottom: 0.75rem; color: var(--color-text-muted);">
            Declared Permissions
          </h3>
          <div style="display: flex; flex-wrap: wrap; gap: 0.5rem;">
            <.permission_badge :for={perm <- @latest.permissions} permission={perm} />
          </div>
        </div>

        <%!-- Tags --%>
        <div :if={@latest.tags != []} style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
          <span
            :for={tag <- @latest.tags}
            style="padding: 0.25rem 0.625rem; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: 9999px; font-size: 0.75rem; color: var(--color-text-muted);"
          >
            {tag}
          </span>
        </div>
      </section>

      <%!-- Version History --%>
      <section style="margin-bottom: 2.5rem;">
        <h2 style="font-size: 1.25rem; margin-bottom: 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid var(--color-border);">
          Version History
        </h2>

        <div :if={@manifests == []} style="color: var(--color-text-muted); padding: 1rem 0;">
          No versions published yet.
        </div>

        <div
          :for={m <- @manifests}
          style="display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 0; border-bottom: 1px solid var(--color-border);"
        >
          <div>
            <span style="font-weight: 600; font-family: monospace;">v{m.version}</span>
            <.status_pill status={m.status} />
          </div>
          <div style="display: flex; gap: 1rem; align-items: center; color: var(--color-text-muted); font-size: 0.8125rem;">
            <.trust_badge score={m.trust_score} />
            <span>{Calendar.strftime(m.created_at, "%b %d, %Y")}</span>
          </div>
        </div>
      </section>

      <%!-- Forked From --%>
      <div
        :if={@latest && @latest.forked_from}
        style="padding: 1rem; background: var(--color-surface); border-radius: 0.5rem; color: var(--color-text-muted); font-size: 0.875rem;"
      >
        🔀 Forked from manifest {@latest.forked_from}
      </div>
    </div>
    """
  end
end
