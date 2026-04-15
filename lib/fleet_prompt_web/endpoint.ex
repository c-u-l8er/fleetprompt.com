defmodule FleetPromptWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :fleet_prompt

  @session_options [
    store: :cookie,
    key: "_fleet_prompt_key",
    signing_salt: "fP7xQm2K",
    same_site: "Lax"
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FleetPromptWeb.Router
end
