defmodule FleetPrompt.MixProject do
  use Mix.Project

  def project do
    [
      app: :fleet_prompt,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {FleetPrompt.Application, []},
      # :inets is needed by Skills.GraphonomousClient.HTTP for the
      # default :httpc transport. Listed here (rather than
      # lazy-starting in the module) so the app is available at the
      # start of the supervision tree.
      extra_applications: [:logger, :runtime_tools, :inets, :ssl]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.2"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.19"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.5"},
      # OS-006 Governance Shim — used by InstallEngine step 4
      # (Delegatic policy check). Path dep: see /delegatic for the
      # authorization kernel.
      {:delegatic, path: "../delegatic"},
      # OS-008 Agent Harness — used by InstallEngine step 5
      # (OpenSentience deploy). Path dep into the vendored copy that
      # Graphonomous carries; hex publication is explicitly not on
      # the roadmap, so the path dep is the permanent pattern.
      {:open_sentience, path: "../graphonomous/deps/open_sentience"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
