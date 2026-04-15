defmodule FleetPromptWeb.WebhookController do
  use FleetPromptWeb, :controller

  alias FleetPrompt.PipelineIntake

  @doc """
  POST /api/pipeline/intake

  Accepts CloudEvents ConsolidationEvent from Agentelic.
  """
  def intake(conn, params) do
    case PipelineIntake.process(params) do
      {:ok, manifest} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "published",
          manifest_id: manifest.id,
          version: manifest.version,
          trust_score: manifest.trust_score
        })

      {:error, :spec_not_registered} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "SPEC_NOT_REGISTERED", message: "Unknown spec hash"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "INTAKE_FAILED", message: inspect(reason)})
    end
  end
end
