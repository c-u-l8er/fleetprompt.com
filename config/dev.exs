import Config

# Shared Supabase instance — all [&] ecosystem products share one DB
# Uses fleet.* schema (migration range 030-039)
config :fleet_prompt, FleetPrompt.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 54322,
  database: "postgres",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  after_connect: {Postgrex, :query!, ["SET search_path TO fleet,amp,public", []]}

config :fleet_prompt, FleetPromptWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kW9pNz3mQ7vR1xLfJ5aGhY8sTdC2uBwE6iOjMlKnXqPrVtAyDcFg0HbIeUmZoSv",
  watchers: []

config :fleet_prompt, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
