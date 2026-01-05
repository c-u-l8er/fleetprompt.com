defmodule FleetPromptWeb.PageControllerTest do
  use FleetPromptWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    # Inertia renders a mount div with a `data-page` JSON payload.
    assert html =~ ~s(data-page=")
    assert html =~ ~s(&quot;component&quot;:&quot;Home&quot;)
    assert html =~ ~s(&quot;message&quot;:&quot;Deploy AI agent fleets in minutes&quot;)
  end
end
