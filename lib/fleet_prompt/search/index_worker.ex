defmodule FleetPrompt.Search.IndexWorker do
  @moduledoc """
  Oban worker that rebuilds the ETS search/category index caches.
  Runs on the :search_index queue.

  Can be triggered:
  - Periodically (e.g., every 10 minutes)
  - After a manifest publish/deprecate/yank
  """

  use Oban.Worker, queue: :search_index, max_attempts: 3

  alias FleetPrompt.SearchIndex

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    SearchIndex.rebuild_categories()
    Logger.info("Search index categories rebuilt")
    :ok
  end

  @doc "Enqueue a search index rebuild job."
  def enqueue do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
