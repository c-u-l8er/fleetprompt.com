defmodule FleetPrompt.Registry do
  @moduledoc """
  Core registry for agent manifests. Handles CRUD operations with
  version immutability enforcement and status lifecycle transitions.

  Publish flow (section 6 of spec):
  1. Manifest validation (changeset)
  2. Spec hash validation (must be present)
  3. Duplicate check (unique constraint on agent_id + version)
  4. Trust computation (4-signal TrustEngine)
  5. Index update (ETS cache)
  6. Audit + notify (AuditWriter + PubSub broadcast)
  """

  import Ecto.Query
  alias FleetPrompt.Repo
  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Manifests.Manifest
  alias FleetPrompt.Trust.Engine, as: TrustEngine
  alias FleetPrompt.AuditWriter
  alias FleetPrompt.Cache

  # -- Agents ------------------------------------------------------------------

  def list_agents(opts \\ []) do
    Agent
    |> maybe_filter_public(opts[:public_only])
    |> maybe_filter_publisher(opts[:publisher_id])
    |> order_by([a], desc: a.created_at)
    |> limit(^(opts[:limit] || 50))
    |> Repo.all()
  end

  def get_agent(id), do: Repo.get(Agent, id)

  def get_agent!(id), do: Repo.get!(Agent, id)

  def get_agent_by_slug(publisher_id, slug) do
    Repo.get_by(Agent, publisher_id: publisher_id, slug: slug)
  end

  def create_agent(attrs) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  # -- Manifests ---------------------------------------------------------------

  @doc """
  Lists manifests for an agent, ordered by version (newest first).
  """
  def list_manifests(agent_id, opts \\ []) do
    Manifest
    |> where([m], m.agent_id == ^agent_id)
    |> maybe_filter_status(opts[:status])
    |> order_by([m], desc: m.created_at)
    |> limit(^(opts[:limit] || 20))
    |> Repo.all()
  end

  def get_manifest(id), do: Repo.get(Manifest, id)

  def get_manifest!(id), do: Repo.get!(Manifest, id)

  @doc """
  Get the latest published manifest for an agent.
  """
  def get_latest_manifest(agent_id) do
    Manifest
    |> where([m], m.agent_id == ^agent_id and m.status == :published)
    |> order_by([m], desc: m.created_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Get a specific version of an agent's manifest.
  """
  def get_manifest_by_version(agent_id, version) do
    Repo.get_by(Manifest, agent_id: agent_id, version: version)
  end

  @doc """
  Full publish flow per spec section 6:

  1. Validates manifest fields (changeset)
  2. Validates spec_hash is present (returns `{:error, :missing_spec_hash}` if absent)
  3. Computes initial trust score from test results + spec data
  4. Inserts with unique constraint on (agent_id, version) for immutability
  5. Caches in ETS
  6. Writes audit event + broadcasts via PubSub

  ## Options

  - `:actor_id` — user ID performing the publish (for audit trail)
  - `:skip_spec_validation` — set true to skip spec_hash requirement (for testing)
  """
  def publish_manifest(attrs, opts \\ []) do
    with :ok <- validate_spec_hash(attrs, opts),
         attrs <- compute_and_attach_trust(attrs),
         attrs <- Map.put(attrs, :status, :published),
         changeset <- Manifest.changeset(%Manifest{}, attrs),
         {:ok, manifest} <- Repo.insert(changeset) do
      # Cache
      Cache.put_manifest(manifest)

      # Audit
      AuditWriter.record_publish(manifest, opts[:actor_id])

      # Broadcast
      Phoenix.PubSub.broadcast(
        FleetPrompt.PubSub,
        "registry:events",
        {:manifest_published, manifest}
      )

      {:ok, manifest}
    end
  end

  @doc """
  Creates a draft manifest (not yet published). No spec validation required.
  """
  def create_draft_manifest(attrs) do
    %Manifest{}
    |> Manifest.changeset(Map.put(attrs, :status, :draft))
    |> Repo.insert()
  end

  @doc """
  Transitions a manifest's status. Enforces valid transitions:
  - draft → published
  - published → deprecated | yanked
  - deprecated → yanked
  """
  def transition_status(%Manifest{} = manifest, new_status, opts \\ []) do
    attrs =
      %{status: new_status}
      |> maybe_add_deprecated_reason(new_status, opts[:reason])

    case manifest
         |> Manifest.status_changeset(attrs)
         |> Repo.update() do
      {:ok, updated} ->
        Cache.put_manifest(updated)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deprecates a published manifest with a reason.
  """
  def deprecate_manifest(%Manifest{} = manifest, reason) do
    transition_status(manifest, :deprecated, reason: reason)
  end

  @doc """
  Yanks a manifest — hides it from search but preserves the record.
  """
  def yank_manifest(%Manifest{} = manifest) do
    transition_status(manifest, :yanked)
  end

  # -- Private -----------------------------------------------------------------

  defp validate_spec_hash(attrs, opts) do
    if Keyword.get(opts, :skip_spec_validation, false) do
      :ok
    else
      case Map.get(attrs, :spec_hash) || Map.get(attrs, "spec_hash") do
        nil -> {:error, :missing_spec_hash}
        "" -> {:error, :missing_spec_hash}
        _hash -> :ok
      end
    end
  end

  defp compute_and_attach_trust(attrs) do
    test_results = Map.get(attrs, :test_results) || Map.get(attrs, "test_results") || %{}

    trust_input = %{
      test_results: %{
        passed: get_nested(test_results, "passed", 0),
        failed: get_nested(test_results, "failed", 0),
        skipped: get_nested(test_results, "skipped", 0)
      },
      spec_hash_valid: (Map.get(attrs, :spec_hash) || Map.get(attrs, "spec_hash")) != nil,
      spec_sections_complete: if(Map.get(attrs, :spec_url), do: 0.5, else: 0.0),
      total_installs: 0,
      active_installs: 0,
      install_success_rate: 0.0,
      avg_uptime: 0.0,
      audit_events_count: 0,
      provenance_complete: (Map.get(attrs, :build_hash) || Map.get(attrs, "build_hash")) != nil,
      permissions_minimal: length(Map.get(attrs, :permissions, []) || []) <= 5
    }

    Map.put(attrs, :trust_score, TrustEngine.compute(trust_input))
  end

  defp get_nested(map, key, default) do
    Map.get(map, key, nil) || Map.get(map, String.to_atom(key), nil) || default
  end

  defp maybe_filter_public(query, true), do: where(query, [a], a.is_public == true)
  defp maybe_filter_public(query, _), do: query

  defp maybe_filter_publisher(query, nil), do: query

  defp maybe_filter_publisher(query, publisher_id),
    do: where(query, [a], a.publisher_id == ^publisher_id)

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status),
    do: where(query, [m], m.status == ^status)

  defp maybe_add_deprecated_reason(attrs, :deprecated, reason) when is_binary(reason),
    do: Map.put(attrs, :deprecated_reason, reason)

  defp maybe_add_deprecated_reason(attrs, _, _), do: attrs
end
