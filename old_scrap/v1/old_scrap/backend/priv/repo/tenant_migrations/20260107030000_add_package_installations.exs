defmodule FleetPrompt.Repo.TenantMigrations.AddPackageInstallations do
  @moduledoc """
  Tenant migration: add `package_installations` table.

  This table is tenant-scoped (created in each tenant schema via `prefix()`), and
  backs `FleetPrompt.Packages.Installation` (multitenancy :context).

  Notes:
  - We use `public.gen_random_uuid()` to avoid UUID default resolution issues in tenant schemas.
  - We avoid cross-schema foreign keys by storing package identity as slug + version.
  """

  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"")

    create_if_not_exists table(:package_installations, primary_key: false, prefix: prefix()) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(:package_slug, :text, null: false)
      add(:package_version, :text, null: false)
      add(:package_name, :text)

      add(:status, :text, null: false, default: "requested")
      add(:enabled, :boolean, null: false, default: true)

      # Public-schema user UUID (no FK across schemas)
      add(:installed_by_user_id, :uuid)
      add(:installed_at, :utc_datetime_usec)

      add(:config, :map, null: false, default: fragment("'{}'::jsonb"))

      add(:idempotency_key, :text)

      add(:last_error, :text)
      add(:last_error_at, :utc_datetime_usec)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    # Uniqueness within a tenant
    create_if_not_exists(
      unique_index(:package_installations, [:package_slug],
        name: "package_installations_unique_package_slug_index",
        prefix: prefix()
      )
    )

    # Idempotency key should be unique when present
    create_if_not_exists(
      unique_index(:package_installations, [:idempotency_key],
        name: "package_installations_unique_idempotency_key_index",
        prefix: prefix(),
        where: "idempotency_key IS NOT NULL"
      )
    )

    # Helpful query indices
    create_if_not_exists(
      index(:package_installations, [:status],
        name: "package_installations_status_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:package_installations, [:enabled],
        name: "package_installations_enabled_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:package_installations, [:installed_at],
        name: "package_installations_installed_at_index",
        prefix: prefix()
      )
    )

    create(
      constraint(:package_installations, :package_installations_status_check,
        prefix: prefix(),
        check: "status IN ('requested','installing','installed','failed','disabled')"
      )
    )
  end

  def down do
    drop_if_exists(
      constraint(:package_installations, :package_installations_status_check, prefix: prefix())
    )

    drop_if_exists(
      index(:package_installations, [:installed_at],
        name: "package_installations_installed_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:package_installations, [:enabled],
        name: "package_installations_enabled_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:package_installations, [:status],
        name: "package_installations_status_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      unique_index(:package_installations, [:idempotency_key],
        name: "package_installations_unique_idempotency_key_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      unique_index(:package_installations, [:package_slug],
        name: "package_installations_unique_package_slug_index",
        prefix: prefix()
      )
    )

    drop_if_exists(table(:package_installations, prefix: prefix()))
  end
end
