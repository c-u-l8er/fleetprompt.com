defmodule FleetPrompt.Trust.Worker do
  @moduledoc """
  GenServer per agent that manages trust score computation.

  Lifecycle:
  1. Computes initial trust score on start
  2. Recomputes when `:recompute` is cast (new data arrives)
  3. Caches current score in ETS via `FleetPrompt.Cache`
  4. Broadcasts score changes via PubSub on `"trust:scores"` topic
  5. Hibernates after 5 minutes of inactivity
  """

  use GenServer

  alias FleetPrompt.Trust.Engine
  alias FleetPrompt.Cache

  @hibernate_after :timer.minutes(5)

  # -- Public API --------------------------------------------------------------

  def start_link(agent_id) do
    GenServer.start_link(__MODULE__, agent_id, name: via(agent_id))
  end

  @doc "Request a trust score recompute for an agent."
  def recompute(agent_id) do
    GenServer.cast(via(agent_id), :recompute)
  end

  @doc "Get the current trust score (from ETS cache, not the GenServer)."
  def get_score(agent_id) do
    Cache.get_trust_score(agent_id)
  end

  @doc "Get the current trust score synchronously from the GenServer state."
  def get_score_sync(agent_id) do
    GenServer.call(via(agent_id), :get_score)
  end

  # -- GenServer callbacks -----------------------------------------------------

  @impl true
  def init(agent_id) do
    state = %{
      agent_id: agent_id,
      score: nil,
      computed_at: nil
    }

    # Compute initial score asynchronously
    send(self(), :compute)

    {:ok, state, @hibernate_after}
  end

  @impl true
  def handle_info(:compute, state) do
    state = do_compute(state)
    {:noreply, state, @hibernate_after}
  end

  @impl true
  def handle_cast(:recompute, state) do
    state = do_compute(state)
    {:noreply, state, @hibernate_after}
  end

  @impl true
  def handle_call(:get_score, _from, state) do
    {:reply, {state.score, state.computed_at}, state, @hibernate_after}
  end

  # -- Private -----------------------------------------------------------------

  defp do_compute(state) do
    input = gather_trust_input(state.agent_id)
    score = Engine.compute(input)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Cache in ETS
    Cache.put_trust_score(state.agent_id, score, now)

    # Broadcast if score changed
    if score != state.score do
      Phoenix.PubSub.broadcast(
        FleetPrompt.PubSub,
        "trust:scores",
        {:trust_updated, state.agent_id, score, now}
      )
    end

    %{state | score: score, computed_at: now}
  end

  defp gather_trust_input(agent_id) do
    # Gather data from various sources to build trust input.
    # For now, builds a minimal input from what's available in the DB.
    # As more integrations come online (PRISM, installs, audits),
    # this will be enriched.
    manifest = FleetPrompt.Registry.get_latest_manifest(agent_id)
    test_results = if manifest, do: manifest.test_results || %{}, else: %{}

    install_counts = count_installs(agent_id)
    audit_count = count_audit_events(agent_id)

    %{
      test_results: %{
        passed: Map.get(test_results, "passed", 0),
        failed: Map.get(test_results, "failed", 0),
        skipped: Map.get(test_results, "skipped", 0)
      },
      spec_hash_valid: manifest != nil and manifest.spec_hash != nil,
      spec_sections_complete: if(manifest && manifest.spec_url, do: 0.5, else: 0.0),
      total_installs: install_counts.total,
      active_installs: install_counts.active,
      install_success_rate: install_counts.success_rate,
      avg_uptime: 0.99,
      audit_events_count: audit_count,
      provenance_complete: manifest != nil and manifest.build_hash != nil,
      permissions_minimal: manifest != nil and length(manifest.permissions || []) <= 5
    }
  end

  defp count_installs(agent_id) do
    import Ecto.Query

    total =
      FleetPrompt.Repo.one(
        from(i in "fleet.installs",
          where: i.agent_id == ^agent_id,
          select: count(i.id)
        )
      ) || 0

    active =
      FleetPrompt.Repo.one(
        from(i in "fleet.installs",
          where: i.agent_id == ^agent_id and is_nil(i.uninstalled_at),
          select: count(i.id)
        )
      ) || 0

    success_rate = if total > 0, do: active / total, else: 0.0

    %{total: total, active: active, success_rate: success_rate}
  end

  defp count_audit_events(agent_id) do
    import Ecto.Query

    FleetPrompt.Repo.one(
      from(e in "fleet.audit_events",
        where: e.target_id == ^agent_id,
        select: count(e.id)
      )
    ) || 0
  end

  defp via(agent_id) do
    {:via, Registry, {FleetPrompt.Trust.Registry, agent_id}}
  end
end
