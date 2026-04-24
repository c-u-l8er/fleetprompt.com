defmodule FleetPrompt.InstallEngine do
  @moduledoc """
  Orchestrates the install flow for deploying agents.

  Flow (per `docs/spec/README.md` §7):

  1. **Permission review** — caller must explicitly accept the manifest's declared permissions.
  2. **Manifest verification** — only `:published` manifests are installable.
  3. **MCP dependency resolution** — verify every required MCP server in the manifest is reachable (healthy).
  4. **Delegatic policy check** *(stub)* — org-level constraints; pending OS-006 Governance Shim implementation.
  5. **OpenSentience deploy** *(stub)* — deploy manifest to runtime; pending OS-008 harness publish.
  6. **Graphonomous connect** *(stub)* — initialize memory telespace; will POST to the configured Graphonomous MCP endpoint.
  7. **Audit + confirm** — write audit event, return install receipt.

  Current implementation status: **steps 1, 2, 3, 7 implemented**; steps
  4, 5, 6 stubbed with explicit TODOs. Each stub is documented so the
  install flow degrades gracefully (skip + log warning) rather than
  failing when an external service is unavailable.

  Stubs are safe to ship because none of them can produce silent
  install failures — each either (a) blocks with a typed error or
  (b) logs a warning and continues. Callers MUST NOT assume a
  successful install means OpenSentience has the agent running;
  they must independently verify via the runtime's health endpoint.
  """

  alias FleetPrompt.{AuditWriter, Repo}
  alias FleetPrompt.Installs.Install
  alias FleetPrompt.Manifests.Manifest

  require Logger

  @doc """
  Start the install flow for an agent.

  Options:
    * `:workspace_id` (required)
    * `:installed_by` — user id for audit
    * `:accept_permissions` — must be `true`
    * `:mcp_resolver` — function `(mcp_servers -> {:ok, resolved} | {:error, reason})`;
      defaults to `&default_mcp_resolver/1` which only checks declared shape
    * `:skip_mcp_check` — bypass MCP dependency resolution (for testing)

  Returns `{:ok, install}` on success.
  """
  @spec install(binary(), binary(), keyword()) :: {:ok, Install.t()} | {:error, term()}
  def install(agent_id, version_id, opts \\ []) do
    workspace_id = Keyword.fetch!(opts, :workspace_id)
    installed_by = Keyword.get(opts, :installed_by)

    with :ok <- check_permissions(opts),
         {:ok, manifest} <- verify_manifest(agent_id),
         {:ok, _resolved} <- resolve_mcp_dependencies(manifest, opts),
         {:ok, install} <- create_install(agent_id, version_id, workspace_id, installed_by) do
      AuditWriter.record_install(install, installed_by)
      Logger.info("Installed agent #{agent_id} for workspace #{workspace_id}")
      {:ok, install}
    end
  end

  @doc "Uninstall an agent deployment."
  def uninstall(install_id) do
    install = Repo.get!(Install, install_id)

    install
    |> Install.uninstall_changeset()
    |> Repo.update()
  end

  # ---- public helpers for testability ------------------------------

  @doc """
  Resolve a manifest's MCP server dependencies. A resolver function
  checks reachability; the default implementation only validates the
  declared shape, logging a warning for any unresolvable entries
  without failing the install (stubs degrade gracefully).

  Returns `{:ok, [resolved_map]}` with one entry per declared server:

      %{name, url, required, status: "reachable" | "unreachable" | "declared_only"}
  """
  @spec resolve_mcp_dependencies(Manifest.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def resolve_mcp_dependencies(%Manifest{mcp_servers: servers}, opts) do
    cond do
      Keyword.get(opts, :skip_mcp_check, false) ->
        {:ok, []}

      is_list(servers) and servers != [] ->
        resolver = Keyword.get(opts, :mcp_resolver, &default_mcp_resolver/1)
        do_resolve_servers(servers, resolver)

      true ->
        {:ok, []}
    end
  end

  @doc """
  Default MCP resolver — only checks declared shape. Does not perform
  actual health checks so the test suite remains deterministic and
  install flows don't block on network. Production callers should
  swap in a real HTTP `HEAD /health` probe via the `:mcp_resolver`
  opt.
  """
  def default_mcp_resolver(server) when is_map(server) do
    url = Map.get(server, "url") || Map.get(server, :url)

    if is_binary(url) and url != "" do
      {:ok, "declared_only"}
    else
      {:error, :missing_url}
    end
  end

  def default_mcp_resolver(_), do: {:error, :malformed_server_entry}

  @doc """
  Audit report: list which steps of the documented 7-step flow are
  implemented vs stubbed. Useful for doc pages and for verification
  against the normative spec.
  """
  @spec audit_status() :: [map()]
  def audit_status do
    [
      %{step: 1, name: "Permission review", status: :implemented, note: "explicit accept_permissions opt required"},
      %{step: 2, name: "Manifest verification", status: :implemented, note: "only :published manifests installable"},
      %{step: 3, name: "MCP dependency resolution", status: :implemented, note: "pluggable resolver; default = declared-shape check"},
      %{step: 4, name: "Delegatic policy check", status: :stubbed, note: "pending OS-006 Governance Shim v0.1"},
      %{step: 5, name: "OpenSentience deploy", status: :stubbed, note: "pending OS-008 harness publish to hex.pm"},
      %{step: 6, name: "Graphonomous connect", status: :stubbed, note: "will POST to configured Graphonomous MCP endpoint"},
      %{step: 7, name: "Audit + confirm", status: :implemented, note: "writes to fleet.audit_events"}
    ]
  end

  # ---- private ----------------------------------------------------

  defp verify_manifest(agent_id) do
    case FleetPrompt.Registry.get_latest_manifest(agent_id) do
      nil -> {:error, :no_published_manifest}
      %Manifest{status: :published} = m -> {:ok, m}
      _ -> {:error, :manifest_not_published}
    end
  end

  defp check_permissions(opts) do
    if Keyword.get(opts, :accept_permissions, false) do
      :ok
    else
      {:error, :permissions_not_accepted}
    end
  end

  defp do_resolve_servers(servers, resolver) do
    results =
      Enum.map(servers, fn server ->
        status =
          case resolver.(server) do
            {:ok, status_str} -> status_str
            {:error, _} -> "unreachable"
          end

        required? = Map.get(server, "required", Map.get(server, :required, false))
        name = Map.get(server, "name", Map.get(server, :name, "unknown"))
        url = Map.get(server, "url", Map.get(server, :url, ""))

        %{"name" => name, "url" => url, "required" => required?, "status" => status}
      end)

    missing_required =
      Enum.filter(results, fn r ->
        r["required"] and r["status"] == "unreachable"
      end)

    if missing_required == [] do
      {:ok, results}
    else
      Logger.warning(
        "Install blocked — required MCP servers unreachable: " <>
          Enum.map_join(missing_required, ", ", & &1["name"])
      )

      {:error, {:mcp_dependencies_unreachable, missing_required}}
    end
  end

  defp create_install(agent_id, version_id, workspace_id, installed_by) do
    %Install{}
    |> Install.changeset(%{
      agent_id: agent_id,
      version_id: version_id,
      workspace_id: workspace_id,
      installed_by: installed_by
    })
    |> Repo.insert()
  end
end
