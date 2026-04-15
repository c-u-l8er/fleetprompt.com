defmodule FleetPrompt.PipelineIntake do
  @moduledoc """
  Dark factory pipeline intake — accepts ConsolidationEvents from Agentelic
  at `POST /api/pipeline/intake`.

  Flow:
  1. Validate CloudEvents envelope (type, source, workspace_id)
  2. Extract artifact manifest + test results
  3. Cross-check spec_hash against SpecPrompt registry
  4. Delegates to Registry.publish_manifest which handles:
     - Trust computation, version immutability, caching, audit, PubSub
  """

  alias FleetPrompt.Registry

  require Logger

  @doc """
  Process an incoming ConsolidationEvent from Agentelic.
  Returns `{:ok, manifest}` on success or `{:error, reason}` on failure.
  """
  def process(%{"type" => "com.agentelic.consolidation.v1"} = event) do
    with {:ok, data} <- extract_data(event),
         {:ok, _spec} <- validate_spec_hash(data),
         {:ok, manifest} <- publish_from_event(data) do
      Logger.info("Pipeline intake: published #{manifest.slug}@#{manifest.version}")
      {:ok, manifest}
    end
  end

  def process(%{"type" => type}) do
    {:error, {:unsupported_event_type, type}}
  end

  def process(_) do
    {:error, :missing_event_type}
  end

  # -- Private -----------------------------------------------------------------

  defp extract_data(%{"data" => data}) when is_map(data), do: {:ok, data}
  defp extract_data(_), do: {:error, :missing_event_data}

  defp validate_spec_hash(%{"spec_hash" => hash}) when is_binary(hash) and hash != "" do
    # TODO: Cross-check against SpecPrompt registry via API
    # For now, accept any non-empty hash
    {:ok, hash}
  end

  defp validate_spec_hash(%{"spec_hash" => nil}), do: {:error, :spec_not_registered}
  defp validate_spec_hash(_), do: {:error, :missing_spec_hash}

  defp publish_from_event(data) do
    attrs = %{
      name: data["name"],
      slug: data["slug"],
      version: data["version"],
      description: data["description"],
      category: data["category"],
      tags: data["tags"] || [],
      spec_url: data["spec_url"],
      spec_hash: data["spec_hash"],
      permissions: data["permissions"] || [],
      mcp_servers: data["mcp_servers"] || [],
      runtime: data["runtime"] || "opensentience",
      build_pipeline: "agentelic",
      build_hash: data["artifact_hash"],
      test_results: data["test_results"] || %{},
      agent_id: data["agent_id"],
      publisher_id: data["publisher_id"]
    }

    # Registry.publish_manifest handles trust computation, caching, audit, PubSub
    case Registry.publish_manifest(attrs) do
      {:ok, manifest} ->
        {:ok, manifest}

      {:error, :missing_spec_hash} ->
        {:error, :spec_not_registered}

      {:error, changeset} ->
        {:error, {:publish_failed, changeset}}
    end
  end
end
