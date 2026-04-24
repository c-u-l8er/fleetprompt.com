defmodule FleetPrompt.Skills.PollWorker do
  @moduledoc """
  Oban worker that polls Graphonomous for successful InteractionTraces
  and crystallizes them into draft FleetPrompt manifests.

  This closes dark-factory loop steps 4→5: machine A records a trace
  in Graphonomous via `&memory.episodic.store`, this worker converts
  it to a FleetPrompt draft, a human or automated reviewer promotes it
  to `:published`, and machine B installs + replays it.

  Cron: configure via the Oban Plugin.Cron spec. Typical cadence is
  every five minutes with overlapping prevention via
  `unique: [period: 300]`.

  ## Args (all optional)

    * `"endpoint"`        — Graphonomous MCP URL override
    * `"state_hash"`      — Fetch traces rooted at a specific StateHash
    * `"limit"`           — Max traces per poll (default 5)
    * `"agent_id"`        — FleetPrompt agent to attach drafts to (falls back to config)
    * `"publisher_id"`    — FleetPrompt publisher to attach drafts to (falls back to config)
  """

  use Oban.Worker, queue: :skills, max_attempts: 3

  alias FleetPrompt.{Registry, Repo}
  alias FleetPrompt.Skills.{Crystallization, Crystallizer, GraphonomousClient}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    client = GraphonomousClient.impl()

    with {:ok, traces} <- client.fetch_successful_traces(client_opts(args)),
         {:ok, summary} <- crystallize_all(traces, args) do
      {:ok, summary}
    else
      {:error, reason} ->
        Logger.warning("Skill crystallization poll failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Crystallize every trace in the given list, skipping any that have
  already been crystallized (idempotent via the
  `(source_type, source_id)` unique constraint on
  `fleet.skill_crystallizations`).

  Returns `{:ok, %{crystallized: N, skipped: M, failed: K}}`.
  """
  @spec crystallize_all([map()], map()) :: {:ok, map()} | {:error, term()}
  def crystallize_all(traces, args) when is_list(traces) and is_map(args) do
    agent_id = args["agent_id"] || configured_agent_id()
    publisher_id = args["publisher_id"] || configured_publisher_id()

    cond do
      is_nil(agent_id) ->
        {:error, :agent_id_not_configured}

      is_nil(publisher_id) ->
        {:error, :publisher_id_not_configured}

      true ->
        results =
          Enum.map(traces, fn trace ->
            crystallize_one(trace,
              agent_id: agent_id,
              publisher_id: publisher_id,
              worker: "FleetPrompt.Skills.PollWorker",
              source_endpoint: args["endpoint"]
            )
          end)

        tally = Enum.frequencies_by(results, fn {status, _} -> status end)

        {:ok,
         %{
           crystallized: Map.get(tally, :ok, 0),
           skipped: Map.get(tally, :skipped, 0),
           failed: Map.get(tally, :error, 0)
         }}
    end
  end

  @doc """
  Crystallize one trace. Returns `{:ok, manifest}` on success,
  `{:skipped, reason}` when a crystallization for the same source
  already exists, or `{:error, reason}` on a transform/publish failure.
  """
  @spec crystallize_one(map(), keyword()) ::
          {:ok, FleetPrompt.Manifests.Manifest.t()}
          | {:skipped, atom()}
          | {:error, term()}
  def crystallize_one(trace, opts) when is_map(trace) and is_list(opts) do
    case Crystallizer.from_trace(trace, opts) do
      {:ok, %{manifest: manifest_attrs, crystallization: cr_attrs}} ->
        insert_pair(manifest_attrs, cr_attrs)

      {:error, {:invalid_trace, reason}} ->
        {:error, {:invalid_trace, reason}}
    end
  end

  # -- internals ----------------------------------------------------

  defp insert_pair(manifest_attrs, cr_attrs) do
    Repo.transaction(fn ->
      case Registry.create_draft_manifest(manifest_attrs) do
        {:ok, manifest} ->
          cr_attrs = Map.put(cr_attrs, :manifest_id, manifest.id)

          case insert_crystallization(cr_attrs) do
            {:ok, _} ->
              {:ok, manifest}

            {:error, %Ecto.Changeset{errors: errors}} ->
              if Keyword.has_key?(errors, :source_id) do
                Repo.rollback({:skipped, :already_crystallized})
              else
                Repo.rollback({:error, errors})
              end
          end

        {:error, changeset} ->
          Repo.rollback({:error, changeset})
      end
    end)
    |> case do
      {:ok, {:ok, manifest}} -> {:ok, manifest}
      {:error, {:skipped, reason}} -> {:skipped, reason}
      {:error, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_crystallization(attrs) do
    %Crystallization{}
    |> Crystallization.changeset(attrs)
    |> Repo.insert()
  end

  defp client_opts(args) do
    []
    |> maybe_put(:endpoint, args["endpoint"])
    |> maybe_put(:state_hash, args["state_hash"])
    |> maybe_put(:limit, args["limit"])
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  defp configured_agent_id,
    do: Application.get_env(:fleet_prompt, :skills_default_agent_id)

  defp configured_publisher_id,
    do: Application.get_env(:fleet_prompt, :skills_default_publisher_id)
end
