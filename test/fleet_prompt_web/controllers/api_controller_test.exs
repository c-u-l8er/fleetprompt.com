defmodule FleetPromptWeb.ApiControllerTest do
  use FleetPromptWeb.ConnCase

  test "GET /api/health returns ok", %{conn: conn} do
    conn = get(conn, ~p"/api/health")

    assert json_response(conn, 200) == %{
             "status" => "ok",
             "service" => "fleetprompt",
             "version" => "0.1.0"
           }
  end
end
