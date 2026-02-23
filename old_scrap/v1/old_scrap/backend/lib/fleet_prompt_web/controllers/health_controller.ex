defmodule FleetPromptWeb.HealthController do
  use FleetPromptWeb, :controller

  @doc """
  Simple health check endpoint.

  Intended for load balancers / platform health checks.
  Returns 200 when the app is up.
  """
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
