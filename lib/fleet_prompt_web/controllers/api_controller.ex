defmodule FleetPromptWeb.ApiController do
  use FleetPromptWeb, :controller

  alias FleetPrompt.Registry
  alias FleetPrompt.Search

  def health(conn, _params) do
    json(conn, %{status: "ok", service: "fleetprompt", version: "0.1.0"})
  end

  def search(conn, params) do
    query = Map.get(params, "q", "")

    opts =
      []
      |> maybe_add(:min_trust, params["min_trust"], &parse_int/1)
      |> maybe_add(:category, params["category"])
      |> maybe_add(:runtime, params["runtime"])
      |> maybe_add(:limit, params["limit"], &parse_int/1)

    agents = Search.search(query, opts)

    json(conn, %{
      results: Enum.map(agents, &serialize_agent/1),
      count: length(agents)
    })
  end

  def show_agent(conn, %{"id" => id}) do
    case Registry.get_agent(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

      agent ->
        agent = FleetPrompt.Repo.preload(agent, [:publisher, :trust_score])
        json(conn, serialize_agent_detail(agent))
    end
  end

  def list_manifests(conn, %{"id" => agent_id}) do
    manifests = Registry.list_manifests(agent_id)

    json(conn, %{
      manifests: Enum.map(manifests, &serialize_manifest/1),
      count: length(manifests)
    })
  end

  def show_manifest(conn, %{"id" => agent_id, "version" => version}) do
    case Registry.get_manifest_by_version(agent_id, version) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Manifest not found"})

      manifest ->
        json(conn, serialize_manifest(manifest))
    end
  end

  # -- Serializers -------------------------------------------------------------

  defp serialize_agent(agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      description: agent.description,
      is_public: agent.is_public,
      download_count: agent.download_count
    }
  end

  defp serialize_agent_detail(agent) do
    base = serialize_agent(agent)

    Map.merge(base, %{
      publisher:
        if(agent.publisher,
          do: %{id: agent.publisher.id, name: agent.publisher.name, slug: agent.publisher.slug},
          else: nil
        ),
      trust_score:
        if(agent.trust_score,
          do: %{
            overall: agent.trust_score.overall_score,
            computed_at: agent.trust_score.computed_at
          },
          else: nil
        ),
      license: agent.license,
      homepage_url: agent.homepage_url,
      repository_url: agent.repository_url,
      icon_url: agent.icon_url,
      created_at: agent.created_at
    })
  end

  defp serialize_manifest(manifest) do
    %{
      id: manifest.id,
      name: manifest.name,
      slug: manifest.slug,
      version: manifest.version,
      description: manifest.description,
      category: manifest.category,
      tags: manifest.tags,
      status: manifest.status,
      trust_score: manifest.trust_score,
      permissions: manifest.permissions,
      runtime: manifest.runtime,
      build_pipeline: manifest.build_pipeline,
      spec_url: manifest.spec_url,
      forked_from: manifest.forked_from,
      created_at: manifest.created_at
    }
  end

  # -- Helpers -----------------------------------------------------------------

  defp maybe_add(opts, key, value, parser \\ nil)
  defp maybe_add(opts, _key, nil, _parser), do: opts
  defp maybe_add(opts, _key, "", _parser), do: opts

  defp maybe_add(opts, key, value, nil), do: [{key, value} | opts]

  defp maybe_add(opts, key, value, parser) do
    case parser.(value) do
      {:ok, parsed} -> [{key, parsed} | opts]
      :error -> opts
    end
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(value) when is_integer(value), do: {:ok, value}
  defp parse_int(_), do: :error
end
