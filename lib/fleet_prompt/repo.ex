defmodule FleetPrompt.Repo do
  use Ecto.Repo,
    otp_app: :fleet_prompt,
    adapter: Ecto.Adapters.Postgres
end
