ExUnit.start(
  # Live crystallization tests require a running Graphonomous MCP
  # server on http://127.0.0.1:4200/mcp (or GRAPHONOMOUS_LIVE_URL).
  # Excluded by default; opt in with:
  #
  #     mix test --include live_crystallization
  exclude: [live_crystallization: true]
)

Ecto.Adapters.SQL.Sandbox.mode(FleetPrompt.Repo, :manual)
