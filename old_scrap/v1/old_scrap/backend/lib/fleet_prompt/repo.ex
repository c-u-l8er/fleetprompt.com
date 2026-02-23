defmodule FleetPrompt.Repo do
  use AshPostgres.Repo,
    otp_app: :fleet_prompt

  def installed_extensions do
    ["uuid-ossp", "citext", "pgcrypto", "ash-functions"]
  end

  # Required for schema-per-tenant multi-tenancy.
  #
  # NOTE: During early bootstrap (before the `organizations` table exists),
  # this may fail. We defensively return an empty tenant list in that case.
  def all_tenants do
    import Ecto.Query

    from(o in "organizations", select: fragment("'org_' || ?", o.slug))
    |> __MODULE__.all()
  rescue
    _ -> []
  end

  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end
end
