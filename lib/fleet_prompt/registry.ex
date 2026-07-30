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
  alias FleetPrompt.Manifests.AgentManifest
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
  #
  # Every agent-keyed query below joins `fleet.agent_manifests`. The manifest
  # itself no longer knows which agent lists it — see
  # `FleetPrompt.Manifests.Manifest` for why. These functions are the
  # marketplace's view of the engine's output and keep their old signatures;
  # the engine's own view is keyed on `(slug, version)`.

  defp listed_by(agent_id) do
    from m in Manifest,
      join: am in AgentManifest,
      on: am.manifest_id == m.id,
      where: am.agent_id == ^agent_id
  end

  @doc """
  Lists manifests listed by an agent, ordered by version (newest first).
  """
  def list_manifests(agent_id, opts \\ []) do
    agent_id
    |> listed_by()
    |> maybe_filter_status(opts[:status])
    |> order_by([m], desc: m.created_at)
    |> limit(^(opts[:limit] || 20))
    |> Repo.all()
  end

  def get_manifest(id), do: Repo.get(Manifest, id)

  def get_manifest!(id), do: Repo.get!(Manifest, id)

  @doc """
  Get the latest published manifest listed by an agent.

  "Latest" means most recently created, with `version` as a tie-break.

  The tie-break is not decoration. `created_at` is `utc_datetime` — second
  precision — so two manifests published in the same second sorted
  non-deterministically and this returned either one. The install flow asks
  this question, so "which version am I installing?" had no stable answer for a
  publish burst. It is a text comparison, not semver: 10.0.0 sorts below 2.0.0.
  Within one second that is arbitrary-but-stable, which is all a tie-break is
  for; across seconds `created_at` decides and publish order wins. Real semver
  ordering is a behaviour change and wants to be chosen, not slipped in under a
  bug fix.
  """
  def get_latest_manifest(agent_id) do
    agent_id
    |> listed_by()
    |> where([m], m.status == :published)
    |> order_by([m], desc: m.created_at, desc: m.version)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Get a specific version of a manifest listed by an agent.
  """
  def get_manifest_by_version(agent_id, version) do
    agent_id
    |> listed_by()
    |> where([m], m.version == ^version)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Links a manifest to an agent — the marketplace's decision to list it.

  Idempotent: relisting the same pair is a no-op rather than an error, because
  a publish that partially succeeded should be safe to retry.
  """
  def list_manifest_for_agent(manifest_id, agent_id, publisher_id) do
    %AgentManifest{}
    |> AgentManifest.changeset(%{
      manifest_id: manifest_id,
      agent_id: agent_id,
      publisher_id: publisher_id
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:agent_id, :manifest_id])
  end

  @doc """
  Full publish flow per spec section 6:

  1. Validates manifest fields (changeset)
  2. Validates spec_hash is present (returns `{:error, :missing_spec_hash}` if absent)
  3. Resolves the workspace this publish happened in
  4. Computes initial trust score from test results + spec data
  5. Inserts the manifest, its listing and its audit event in one transaction
     — unique constraint on (slug, version) gives version immutability
  6. Caches in ETS and broadcasts via PubSub, once the transaction has committed

  The manifest, the listing and the audit event are written together on
  purpose. The audit write used to be a bare call whose result was discarded,
  and `audit_events.workspace_id` is NOT NULL — so a publish that could not
  resolve a workspace produced a manifest with no provenance record and
  returned `{:ok, manifest}`. Nothing failed, which is why nobody noticed. It
  became reachable when a manifest stopped requiring an agent, since the
  workspace was derived from the agent.

  ## Options

  - `:actor_id` — user ID performing the publish (for audit trail)
  - `:workspace_id` — publish workspace; defaults to the listing agent's
  - `:skip_spec_validation` — set true to skip spec_hash requirement (for testing)
  """
  def publish_manifest(attrs, opts \\ []) do
    {agent_id, publisher_id, attrs} = pop_listing(attrs)

    with :ok <- validate_spec_hash(attrs, opts),
         {:ok, workspace_id} <- resolve_workspace(agent_id, opts),
         attrs <- compute_and_attach_trust(attrs),
         attrs <- Map.put(attrs, :status, :published),
         {:ok, manifest} <-
           insert_published(attrs, agent_id, publisher_id, workspace_id, opts) do
      Cache.put_manifest(manifest, agent_id)

      Phoenix.PubSub.broadcast(
        FleetPrompt.PubSub,
        "registry:events",
        {:manifest_published, manifest}
      )

      {:ok, manifest}
    end
  end

  defp insert_published(attrs, agent_id, publisher_id, workspace_id, opts) do
    Repo.transaction(fn ->
      with {:ok, manifest} <- %Manifest{} |> Manifest.changeset(attrs) |> Repo.insert(),
           # Listing. The manifest is the engine's; this row is the marketplace
           # claiming it. Publishing without an agent is a legal engine
           # operation, so a missing agent_id skips the listing rather than
           # failing the publish.
           {:ok, _listing} <- maybe_list(manifest, agent_id, publisher_id),
           {:ok, _event} <-
             AuditWriter.record_publish(manifest, opts[:actor_id], workspace_id) do
        manifest
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_list(_manifest, nil, _publisher_id), do: {:ok, nil}

  defp maybe_list(manifest, agent_id, publisher_id),
    do: list_manifest_for_agent(manifest.id, agent_id, publisher_id)

  defp resolve_workspace(agent_id, opts) do
    case Keyword.get(opts, :workspace_id) || workspace_id_of(agent_id) do
      nil -> {:error, :missing_workspace_id}
      id -> {:ok, id}
    end
  end

  @doc """
  Creates a draft manifest (not yet published). No spec validation required.

  Accepts `:agent_id` / `:publisher_id` and, when both are present, links the
  draft to the agent. They are no longer manifest fields, so a caller with
  neither still gets a manifest — a built-but-unlisted draft.
  """
  def create_draft_manifest(attrs) do
    {agent_id, publisher_id, attrs} = pop_listing(attrs)

    case %Manifest{}
         |> Manifest.changeset(Map.put(attrs, :status, :draft))
         |> Repo.insert() do
      {:ok, manifest} ->
        if agent_id, do: list_manifest_for_agent(manifest.id, agent_id, publisher_id)
        {:ok, manifest}

      {:error, changeset} ->
        {:error, changeset}
    end
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
        # Re-cache under every agent listing this manifest. There is usually
        # one; there can be none, and then there is nothing to cache.
        Enum.each(agents_listing(updated.id), &Cache.put_manifest(updated, &1))
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

  # `agent_id` and `publisher_id` are still how callers talk about a publish —
  # they just aren't manifest columns any more. Split them off before the
  # changeset sees them, accepting either key form because callers arrive from
  # JSON (MCP, pipeline intake) and from Elixir (crystallizer) alike.
  defp pop_listing(attrs) do
    {agent_id, attrs} = pop_either(attrs, :agent_id, "agent_id")
    {publisher_id, attrs} = pop_either(attrs, :publisher_id, "publisher_id")
    {agent_id, publisher_id, attrs}
  end

  defp pop_either(attrs, atom_key, string_key) do
    case Map.pop(attrs, atom_key) do
      {nil, rest} -> Map.pop(rest, string_key)
      {value, rest} -> {value, Map.delete(rest, string_key)}
    end
  end

  defp agents_listing(manifest_id) do
    AgentManifest
    |> where([am], am.manifest_id == ^manifest_id)
    |> select([am], am.agent_id)
    |> Repo.all()
  end

  defp workspace_id_of(nil), do: nil

  defp workspace_id_of(agent_id) do
    case Repo.get(Agent, agent_id) do
      nil -> nil
      agent -> agent.workspace_id
    end
  end

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
