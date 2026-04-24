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
      # (Delegatic policy check). Sourced from the public c-u-l8er/
      # delegatic-engine github repo so production Docker builds don't
      # need a multi-project build context.
      {:delegatic, git: "https://github.com/c-u-l8er/delegatic-engine.git", branch: "main"},
      # OS-008 Agent Harness — used by InstallEngine step 5
      # (OpenSentience deploy). Sourced from c-u-l8er/opensentience.org
      # which carries the mix library at its repo root. Hex publication
      # is explicitly not on the roadmap; git-dep is the permanent
      # pattern.
      {:open_sentience,
       git: "https://github.com/c-u-l8er/opensentience.org.git", branch: "main"}
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
