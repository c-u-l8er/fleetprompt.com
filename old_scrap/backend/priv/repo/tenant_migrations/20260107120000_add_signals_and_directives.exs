defmodule FleetPrompt.Repo.TenantMigrations.AddSignalsAndDirectives do
  @moduledoc """
  Tenant migration: add `signals` and `directives` tables.

  These tables are tenant-scoped (created in each tenant schema via `prefix()`), and
  back Phase 2B platform primitives:
  - `FleetPrompt.Signals.Signal` (persisted immutable facts)
  - `FleetPrompt.Directives.Directive` (persisted auditable commands)

  Notes:
  - We use `public.gen_random_uuid()` to avoid UUID default resolution issues in tenant schemas.
  - We default JSON fields to `'{}'::jsonb` and timestamps to UTC.
  - We avoid cross-schema foreign keys; references to public-schema user ids are stored as UUIDs without FKs.
  """

  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"")

    # -----------------------
    # signals (append-only)
    # -----------------------
    create_if_not_exists table(:signals, primary_key: false, prefix: prefix()) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(:name, :text, null: false)
      add(:dedupe_key, :text)

      add(:payload, :map, null: false, default: fragment("'{}'::jsonb"))
      add(:metadata, :map, null: false, default: fragment("'{}'::jsonb"))

      add(:occurred_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:correlation_id, :text)
      add(:causation_id, :text)

      add(:actor_type, :text)
      add(:actor_id, :text)

      add(:subject_type, :text)
      add(:subject_id, :text)

      add(:source, :text)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create_if_not_exists(
      unique_index(:signals, [:dedupe_key],
        name: "signals_unique_dedupe_key_index",
        prefix: prefix(),
        where: "dedupe_key IS NOT NULL"
      )
    )

    create_if_not_exists(
      index(:signals, [:name],
        name: "signals_name_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:signals, [:occurred_at],
        name: "signals_occurred_at_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:signals, [:inserted_at],
        name: "signals_inserted_at_index",
        prefix: prefix()
      )
    )

    # Basic check constraints (idempotent via conditional SQL)
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'signals_name_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".signals
          ADD CONSTRAINT signals_name_nonempty_check
          CHECK (char_length(name) > 0);
      END IF;
    END $$;
    """)

    # -----------------------
    # directives (auditable commands)
    # -----------------------
    create_if_not_exists table(:directives, primary_key: false, prefix: prefix()) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(:name, :text, null: false)
      add(:idempotency_key, :text)

      add(:status, :text, null: false, default: "requested")

      add(:scheduled_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)

      add(:payload, :map, null: false, default: fragment("'{}'::jsonb"))
      add(:metadata, :map, null: false, default: fragment("'{}'::jsonb"))
      add(:result, :map, null: false, default: fragment("'{}'::jsonb"))

      add(:last_error, :text)
      add(:last_error_at, :utc_datetime_usec)

      # Public-schema user UUID (no FK across schemas)
      add(:requested_by_user_id, :uuid)

      add(:attempt, :integer, null: false, default: 0)
      add(:max_attempts, :integer, null: false, default: 10)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create_if_not_exists(
      unique_index(:directives, [:idempotency_key],
        name: "directives_unique_idempotency_key_index",
        prefix: prefix(),
        where: "idempotency_key IS NOT NULL"
      )
    )

    create_if_not_exists(
      index(:directives, [:status],
        name: "directives_status_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:directives, [:scheduled_at],
        name: "directives_scheduled_at_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:directives, [:inserted_at],
        name: "directives_inserted_at_index",
        prefix: prefix()
      )
    )

    # Status constraint (idempotent via conditional SQL)
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'directives_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".directives
          ADD CONSTRAINT directives_status_check
          CHECK (status IN ('requested','running','succeeded','failed','canceled'));
      END IF;
    END $$;
    """)

    # Basic guardrails
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'directives_name_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".directives
          ADD CONSTRAINT directives_name_nonempty_check
          CHECK (char_length(name) > 0);
      END IF;
    END $$;
    """)
  end

  def down do
    # Drop constraints (best-effort, idempotent)
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'directives_name_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".directives DROP CONSTRAINT directives_name_nonempty_check;
      END IF;

      IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'directives_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".directives DROP CONSTRAINT directives_status_check;
      END IF;

      IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'signals_name_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".signals DROP CONSTRAINT signals_name_nonempty_check;
      END IF;
    END $$;
    """)

    # Drop indices (idempotent)
    drop_if_exists(
      index(:directives, [:inserted_at],
        name: "directives_inserted_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:directives, [:scheduled_at],
        name: "directives_scheduled_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:directives, [:status],
        name: "directives_status_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      unique_index(:directives, [:idempotency_key],
        name: "directives_unique_idempotency_key_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:signals, [:inserted_at],
        name: "signals_inserted_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:signals, [:occurred_at],
        name: "signals_occurred_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:signals, [:name],
        name: "signals_name_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      unique_index(:signals, [:dedupe_key],
        name: "signals_unique_dedupe_key_index",
        prefix: prefix()
      )
    )

    # Drop tables
    drop_if_exists(table(:directives, prefix: prefix()))
    drop_if_exists(table(:signals, prefix: prefix()))
  end
end
