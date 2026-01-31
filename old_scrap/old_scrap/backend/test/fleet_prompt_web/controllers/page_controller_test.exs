defmodule FleetPromptWeb.PageControllerTest do
  use FleetPromptWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    # Inertia renders a mount div with a `data-page` JSON payload.
    assert html =~ ~s(data-page=")

    # The `data-page` attribute value is HTML-escaped, so we match against `"...`.
    expected_component =
      "&" <> "quot;component" <> "&" <> "quot;:" <> "&" <> "quot;Home" <> "&" <> "quot;"

    expected_message =
      "&" <>
        "quot;message" <> "&" <> "quot;:" <> "&" <>
        "quot;Deploy fleets of AI agents in minutes" <> "&" <> "quot;"

    assert html =~ expected_component
    assert html =~ expected_message
  end
end
