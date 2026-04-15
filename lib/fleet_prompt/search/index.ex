defmodule FleetPrompt.SearchIndex do
  @moduledoc """
  Manages the search index state in ETS for fast category lookups
  and search result caching.

  The PostgreSQL search_vector generated column handles full-text indexing
  automatically. This module manages the supplementary ETS caches:
  - `:fp_categories` — category_slug → [agent_id]
  - `:fp_search_index` — reserved for future trigram caching
  """

  alias FleetPrompt.Repo
  alias FleetPrompt.Cache

  import Ecto.Query

  @doc """
  Rebuild the category index from the database.
  Called on startup and periodically via Oban.
  """
  def rebuild_categories do
    query =
      from(m in "fleet.manifests",
        where: m.status == "published" and not is_nil(m.category),
        group_by: m.category,
        select: {m.category, fragment("array_agg(?)", m.agent_id)}
      )

    Repo.all(query)
    |> Enum.each(fn {category, agent_ids} ->
      Cache.put_category(category, agent_ids)
    end)

    :ok
  end

  @doc """
  Update the category index for a single agent after publish/deprecate.
  """
  def update_agent_category(agent_id, category) when is_binary(category) do
    case Cache.get_category(category) do
      {:ok, agent_ids} ->
        unless agent_id in agent_ids do
          Cache.put_category(category, [agent_id | agent_ids])
        end

      :miss ->
        Cache.put_category(category, [agent_id])
    end

    :ok
  end

  def update_agent_category(_agent_id, _category), do: :ok

  @doc """
  Remove an agent from the category index (on yank/deprecate).
  """
  def remove_agent_from_category(agent_id, category) when is_binary(category) do
    case Cache.get_category(category) do
      {:ok, agent_ids} ->
        Cache.put_category(category, List.delete(agent_ids, agent_id))

      :miss ->
        :ok
    end
  end

  def remove_agent_from_category(_agent_id, _category), do: :ok
end
