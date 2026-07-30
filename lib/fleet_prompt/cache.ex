defmodule FleetPrompt.Cache do
  @moduledoc """
  ETS-backed hot cache for frequently accessed registry data.

  Tables:
  - `:fp_manifests`    — {agent_id, version} → manifest map
  - `:fp_trust_scores` — agent_id → {score, computed_at}
  - `:fp_search_index` — trigram → [agent_id]
  - `:fp_categories`   — category_slug → [agent_id]
  """

  use GenServer

  @tables [:fp_manifests, :fp_trust_scores, :fp_search_index, :fp_categories]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # -- Public API --------------------------------------------------------------

  @doc """
  Cache a manifest by {agent_id, version}.

  This is a marketplace cache — it answers "what is this agent serving?" — so
  the agent is supplied by the caller. It used to be read off the manifest, back
  when a manifest carried the agent that listed it. An unlisted manifest is not
  cached, because there is no agent to look it up by.
  """
  def put_manifest(manifest, agent_id)

  def put_manifest(_manifest, nil), do: :ok

  def put_manifest(%{version: version} = manifest, agent_id) do
    :ets.insert(:fp_manifests, {{agent_id, version}, manifest})
    :ok
  end

  @doc "Look up a manifest from cache."
  def get_manifest(agent_id, version) do
    case :ets.lookup(:fp_manifests, {agent_id, version}) do
      [{_key, manifest}] -> {:ok, manifest}
      [] -> :miss
    end
  end

  @doc "Cache a trust score for an agent."
  def put_trust_score(agent_id, score, computed_at \\ DateTime.utc_now()) do
    :ets.insert(:fp_trust_scores, {agent_id, {score, computed_at}})
    :ok
  end

  @doc "Look up a trust score from cache."
  def get_trust_score(agent_id) do
    case :ets.lookup(:fp_trust_scores, agent_id) do
      [{_key, {score, computed_at}}] -> {:ok, score, computed_at}
      [] -> :miss
    end
  end

  @doc "Cache agents under a category slug."
  def put_category(slug, agent_ids) do
    :ets.insert(:fp_categories, {slug, agent_ids})
    :ok
  end

  @doc "Look up agents for a category."
  def get_category(slug) do
    case :ets.lookup(:fp_categories, slug) do
      [{_key, agent_ids}] -> {:ok, agent_ids}
      [] -> :miss
    end
  end

  @doc "Clear all caches."
  def flush_all do
    Enum.each(@tables, &:ets.delete_all_objects/1)
    :ok
  end

  # -- GenServer callbacks -----------------------------------------------------

  @impl true
  def init(_opts) do
    tables =
      Enum.map(@tables, fn name ->
        :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
      end)

    {:ok, %{tables: tables}}
  end
end
