import Config

config :fleet_prompt, FleetPrompt.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 54322,
  database: "postgres",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  after_connect: {Postgrex, :query!, ["SET search_path TO fleet,amp,public", []]}

config :fleet_prompt, FleetPromptWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4012],
  secret_key_base: "kW9pNz3mQ7vR1xLfJ5aGhY8sTdC2uBwE6iOjMlKnXqPrVtAyDcFg0HbIeUmZoSv",
  server: false

config :fleet_prompt, Oban, testing: :inline

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
