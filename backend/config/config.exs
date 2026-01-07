# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fleet_prompt,
  ecto_repos: [FleetPrompt.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    FleetPrompt.Accounts,
    FleetPrompt.Agents,
    FleetPrompt.Skills,
    FleetPrompt.Workflows,
    FleetPrompt.Packages,
    FleetPrompt.Forums,
    FleetPrompt.Signals,
    FleetPrompt.Directives
  ]

# Configure the endpoint
config :fleet_prompt, FleetPromptWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FleetPromptWeb.ErrorHTML, json: FleetPromptWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FleetPrompt.PubSub,
  live_view: [signing_salt: "GIeo_fKca-BhFCHE"]

# Configure Inertia
config :inertia,
  endpoint: FleetPromptWeb.Endpoint,
  static_paths: ["/assets/app.js", "/assets/app.css"],
  default_version: "1",
  ssr: false,
  raise_on_ssr_failure: false

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fleet_prompt, FleetPrompt.Mailer, adapter: Swoosh.Adapters.Local

# Configure Oban
config :fleet_prompt, Oban,
  repo: FleetPrompt.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ],
  queues: [
    default: 10
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
