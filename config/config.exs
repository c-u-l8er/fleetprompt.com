import Config

config :fleet_prompt,
  ecto_repos: [FleetPrompt.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :fleet_prompt, FleetPromptWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FleetPromptWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FleetPrompt.PubSub,
  live_view: [signing_salt: "fP7xQm2K"]

config :fleet_prompt, Oban,
  repo: FleetPrompt.Repo,
  prefix: "fleet",
  queues: [trust: 10, webhooks: 5, search_index: 3]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
