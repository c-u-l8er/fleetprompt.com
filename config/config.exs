import Config

config :fleet_prompt,
  ecto_repos: [FleetPrompt.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# KILN is a library with no Repo, no supervision tree and no config of its own.
# FleetPrompt is its host, so FleetPrompt supplies them. `schema_prefix` is
# "fleet" because that is where the engine's tables live today — next to the
# marketplace that used to own them. KILN's own range is `kiln.*` (migrations
# 110–119, allocated and unused); moving them is a data migration on a database
# other work is live against, so it is a deliberate decision rather than a side
# effect of extracting the code. Ecto resolves @schema_prefix at compile time,
# so changing this line means `mix deps.compile kiln --force`.
config :kiln,
  repo: FleetPrompt.Repo,
  schema_prefix: "fleet"

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
