defmodule FleetPrompt.Search do
  @moduledoc """
  Full-text search for agents using PostgreSQL ts_vector + pg_trgm.

  Search combines:
  - ts_vector ranked full-text search (weighted: name A, description B)
  - pg_trgm fuzzy matching for typo tolerance (similarity > 0.3)

  Results are ordered by ts_rank DESC, then trust_score DESC.
  """

  import Ecto.Query
  alias FleetPrompt.Repo
  alias FleetPrompt.Agents.Agent

  @doc """
  Search for agents by query string with optional filters.

  ## Options

  - `:min_trust` — minimum trust score (default: 0)
  - `:category` — filter by category slug
  - `:runtime` — filter by runtime (e.g., "opensentience")
  - `:limit` — max results (default: 20)
  - `:published_only` — only return agents with published manifests (default: true)
  """
  def search(query_term, opts \\ []) do
    min_trust = Keyword.get(opts, :min_trust, 0)
    category = Keyword.get(opts, :category)
    runtime = Keyword.get(opts, :runtime)
    limit = Keyword.get(opts, :limit, 20)

    base =
      from(a in Agent,
        join: m in assoc(a, :manifests),
        as: :manifest,
        where: m.status == :published,
        where: a.is_public == true,
        where: m.trust_score >= ^min_trust or is_nil(m.trust_score),
        distinct: a.id
      )

    base
    |> maybe_filter_category(category)
    |> maybe_filter_runtime(runtime)
    |> apply_search(query_term)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Quick search by name only (for autocomplete / typeahead).
  Uses pg_trgm similarity for fuzzy matching.
  """
  def autocomplete(term, limit \\ 10) do
    from(a in Agent,
      where: a.is_public == true,
      where: fragment("similarity(?, ?) > 0.3", a.name, ^term),
      order_by: [desc: fragment("similarity(?, ?)", a.name, ^term)],
      limit: ^limit,
      select: %{id: a.id, name: a.name, slug: a.slug, description: a.description}
    )
    |> Repo.all()
  end

  # -- Private -----------------------------------------------------------------

  defp apply_search(queryable, nil), do: queryable
  defp apply_search(queryable, ""), do: queryable

  defp apply_search(queryable, term) do
    from([a, manifest: m] in queryable,
      where:
        fragment(
          "? @@ plainto_tsquery('english', ?) OR similarity(?, ?) > 0.3",
          a.search_vector,
          ^term,
          a.name,
          ^term
        ),
      order_by: [
        desc: fragment("ts_rank(?, plainto_tsquery('english', ?))", a.search_vector, ^term),
        desc: m.trust_score
      ]
    )
  end

  defp maybe_filter_category(q, nil), do: q

  defp maybe_filter_category(q, category_slug) do
    from([a, manifest: m] in q,
      where: m.category == ^category_slug
    )
  end

  defp maybe_filter_runtime(q, nil), do: q

  defp maybe_filter_runtime(q, runtime) do
    from([a, manifest: m] in q,
      where: m.runtime == ^runtime
    )
  end
end
