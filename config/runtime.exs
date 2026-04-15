import Config

if System.get_env("PHX_SERVER") do
  config :fleet_prompt, FleetPromptWeb.Endpoint, server: true
end

config :fleet_prompt, FleetPromptWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4002"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :fleet_prompt, FleetPrompt.Repo,
    ssl: [verify: :verify_none],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    prepare: :unnamed,
    after_connect: {Postgrex, :query!, ["SET search_path TO fleet,amp,public", []]}

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "fleetprompt.com"

  config :fleet_prompt, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fleet_prompt, FleetPromptWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
