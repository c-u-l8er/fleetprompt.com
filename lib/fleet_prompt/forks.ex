defmodule FleetPrompt.Forks do
  @moduledoc """
  Fork-and-customize workflow for public agents.

  Any public agent can be forked. Forking creates a new agent under
  the forker's publisher account with `forked_from` set to the source
  manifest ID. Trust scores for forks start at 0.
  """

  alias FleetPrompt.Repo
  alias FleetPrompt.Manifests.Manifest

  @doc """
  Fork a published manifest into a new draft manifest under a different publisher.

  The forked manifest:
  - Gets a new agent_id (must be provided)
  - Starts as `:draft` status
  - Has `forked_from` set to the source manifest ID
  - Version resets to "0.1.0"
  - Trust score starts at nil (will be 0 when computed)

  ## Options

  - `:name` — override the forked agent name (default: "Original Name (fork)")
  - `:slug` — override the forked agent slug (default: "original-slug-fork")
  - `:agent_id` — the agent to attach the forked manifest to (required)
  """
  def fork(source_manifest_id, publisher_id, opts \\ []) do
    source = Repo.get!(Manifest, source_manifest_id)

    unless source.status == :published do
      raise ArgumentError, "can only fork published manifests"
    end

    agent_id = Keyword.fetch!(opts, :agent_id)
    new_slug = Keyword.get(opts, :slug, "#{source.slug}-fork")
    new_name = Keyword.get(opts, :name, "#{source.name} (fork)")

    %Manifest{}
    |> Manifest.changeset(%{
      name: new_name,
      slug: new_slug,
      version: "0.1.0",
      description: source.description,
      category: source.category,
      tags: source.tags,
      spec_url: source.spec_url,
      permissions: source.permissions,
      mcp_servers: source.mcp_servers,
      runtime: source.runtime,
      agent_id: agent_id,
      publisher_id: publisher_id,
      forked_from: source_manifest_id,
      status: :draft
    })
    |> Repo.insert()
  end
end
