defmodule FleetPrompt.MCP.Tools do
  @moduledoc """
  MCP tool definitions for the FleetPrompt registry.

  Seven tools exposed via MCP JSON-RPC:
  - registry_search — search agents by capability/domain/trust
  - registry_publish — publish tested agent with manifest
  - registry_install — deploy to OpenSentience runtime
  - registry_inspect — view manifest, permissions, trust, provenance
  - registry_versions — list version history
  - registry_trust — query or recompute trust score
  - registry_fork — fork public agent for customization
  """

  alias FleetPrompt.Registry
  alias FleetPrompt.Search
  alias FleetPrompt.Trust
  alias FleetPrompt.Forks
  alias FleetPrompt.InstallEngine

  @doc "Returns the list of MCP tool definitions."
  def definitions do
    [
      %{
        name: "registry_search",
        description: "Search agents by capability, domain, or trust level",
        inputSchema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Search query"},
            min_trust: %{type: "integer", default: 0},
            category: %{type: "string"},
            runtime: %{type: "string"},
            limit: %{type: "integer", default: 20}
          },
          required: ["query"]
        }
      },
      %{
        name: "registry_publish",
        description: "Publish a tested agent with its manifest",
        inputSchema: %{
          type: "object",
          properties: %{
            manifest: %{type: "object", description: "Full manifest object"},
            spec_url: %{type: "string"},
            test_results: %{type: "object"}
          },
          required: ["manifest"]
        }
      },
      %{
        name: "registry_install",
        description: "Deploy agent to OpenSentience runtime",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            version: %{type: "string", default: "latest"},
            runtime_url: %{type: "string"},
            accept_permissions: %{type: "boolean"}
          },
          required: ["agent_id", "runtime_url", "accept_permissions"]
        }
      },
      %{
        name: "registry_inspect",
        description: "View manifest, permissions, trust score, and provenance",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            version: %{type: "string", default: "latest"}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "registry_versions",
        description: "List version history with changelogs",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            limit: %{type: "integer", default: 10}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "registry_trust",
        description: "Query or force-recompute trust score",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            recompute: %{type: "boolean", default: false}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "registry_fork",
        description: "Fork a public agent for customization",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string"},
            version: %{type: "string", default: "latest"},
            new_slug: %{type: "string"}
          },
          required: ["agent_id", "new_slug"]
        }
      }
    ]
  end

  @doc "Handle a tool call by name."
  def call("registry_search", args) do
    opts =
      [
        min_trust: Map.get(args, "min_trust", 0),
        limit: Map.get(args, "limit", 20)
      ]
      |> maybe_add_opt(:category, args["category"])
      |> maybe_add_opt(:runtime, args["runtime"])

    agents = Search.search(args["query"], opts)

    {:ok,
     %{
       results:
         Enum.map(agents, fn a ->
           %{id: a.id, name: a.name, slug: a.slug, description: a.description}
         end),
       count: length(agents)
     }}
  end

  def call("registry_inspect", args) do
    agent_id = args["agent_id"]
    version = Map.get(args, "version", "latest")

    manifest =
      if version == "latest" do
        Registry.get_latest_manifest(agent_id)
      else
        Registry.get_manifest_by_version(agent_id, version)
      end

    case manifest do
      nil ->
        {:error, "Manifest not found"}

      m ->
        {:ok,
         %{
           id: m.id,
           name: m.name,
           version: m.version,
           status: m.status,
           trust_score: m.trust_score,
           permissions: m.permissions,
           spec_url: m.spec_url,
           runtime: m.runtime,
           forked_from: m.forked_from
         }}
    end
  end

  def call("registry_versions", args) do
    manifests = Registry.list_manifests(args["agent_id"], limit: Map.get(args, "limit", 10))

    {:ok,
     %{
       versions:
         Enum.map(manifests, fn m ->
           %{
             version: m.version,
             status: m.status,
             trust_score: m.trust_score,
             created_at: m.created_at
           }
         end)
     }}
  end

  def call("registry_trust", args) do
    agent_id = args["agent_id"]

    if Map.get(args, "recompute", false) do
      Trust.Supervisor.ensure_worker(agent_id)
      Trust.Worker.recompute(agent_id)
    end

    case Trust.Worker.get_score(agent_id) do
      {:ok, score, computed_at} ->
        {:ok, %{agent_id: agent_id, trust_score: score, computed_at: computed_at}}

      :miss ->
        {:ok, %{agent_id: agent_id, trust_score: nil, message: "No score computed yet"}}
    end
  end

  def call("registry_publish", args) do
    manifest_data = Map.get(args, "manifest", %{})

    attrs =
      manifest_data
      |> Map.put(:spec_url, args["spec_url"])
      |> Map.put(:test_results, args["test_results"])

    case Registry.publish_manifest(attrs) do
      {:ok, manifest} ->
        {:ok,
         %{
           id: manifest.id,
           version: manifest.version,
           trust_score: manifest.trust_score,
           status: manifest.status
         }}

      {:error, :missing_spec_hash} ->
        {:error, "spec_hash is required for publishing"}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:error, "Publish failed: #{errors}"}
    end
  end

  def call("registry_install", args) do
    agent_id = args["agent_id"]
    accept = Map.get(args, "accept_permissions", false)

    # Resolve version
    manifest =
      case Map.get(args, "version", "latest") do
        "latest" -> Registry.get_latest_manifest(agent_id)
        version -> Registry.get_manifest_by_version(agent_id, version)
      end

    case manifest do
      nil ->
        {:error, "No published manifest found for agent"}

      m ->
        # Need a version_id for the install — look up the agent_version record
        case InstallEngine.install(agent_id, m.id,
               workspace_id: args["workspace_id"] || "00000000-0000-0000-0000-000000000000",
               accept_permissions: accept
             ) do
          {:ok, install} ->
            {:ok,
             %{
               install_id: install.id,
               agent_id: agent_id,
               status: "installed",
               runtime_url: args["runtime_url"]
             }}

          {:error, :permissions_not_accepted} ->
            {:error,
             "You must accept permissions before installing. Set accept_permissions: true"}

          {:error, reason} ->
            {:error, "Install failed: #{inspect(reason)}"}
        end
    end
  end

  def call("registry_fork", args) do
    agent_id = args["agent_id"]
    new_slug = args["new_slug"]

    # Get the source manifest
    manifest =
      case Map.get(args, "version", "latest") do
        "latest" -> Registry.get_latest_manifest(agent_id)
        version -> Registry.get_manifest_by_version(agent_id, version)
      end

    case manifest do
      nil ->
        {:error, "No published manifest found to fork"}

      source ->
        publisher_id = args["publisher_id"] || source.publisher_id
        fork_agent_id = args["fork_agent_id"] || agent_id

        case Forks.fork(source.id, publisher_id,
               slug: new_slug,
               agent_id: fork_agent_id
             ) do
          {:ok, forked} ->
            {:ok,
             %{
               id: forked.id,
               slug: forked.slug,
               version: forked.version,
               forked_from: forked.forked_from,
               status: forked.status,
               trust_score: nil
             }}

          {:error, changeset} ->
            errors = format_changeset_errors(changeset)
            {:error, "Fork failed: #{errors}"}
        end
    end
  end

  def call(tool_name, _args) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_changeset_errors(other), do: inspect(other)

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: [{key, value} | opts]
end
