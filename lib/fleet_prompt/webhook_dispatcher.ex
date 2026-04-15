defmodule FleetPrompt.WebhookDispatcher do
  @moduledoc """
  Oban worker for async webhook delivery with retry and backoff.
  Dispatches registry events (publish, install, fork, trust_change)
  to registered webhook endpoints.
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event, "url" => url, "payload" => payload}}) do
    case Req.post(url,
           json: %{event: event, payload: payload, timestamp: DateTime.utc_now()},
           receive_timeout: 10_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("Webhook #{event} to #{url} returned #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("Webhook #{event} to #{url} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Enqueue a webhook delivery job."
  def dispatch(event, url, payload) do
    %{event: event, url: url, payload: payload}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
