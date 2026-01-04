defmodule FleetPrompt.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  # NOTE:
  # Oban requires database tables (oban_jobs and oban_peers, plus indexes/triggers)
  # to exist before the Oban supervision tree starts. This migration installs them
  # using Oban's built-in versioned migrations.
  #
  # If you ever need to rollback completely, `down/0` drops everything back to v1.
  #
  # Version choice:
  # Use a recent migration version compatible with Oban 2.20.x. If you upgrade Oban
  # later and it requires additional migrations, bump the version in `up/0`.
  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
