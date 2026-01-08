defmodule FleetPrompt.Repo.TenantMigrations.RelaxExecutionOutputNotNull do
  use Ecto.Migration

  @moduledoc """
  Tenant-scoped migration: relax NOT NULL constraint on `executions.output`.

  Why:
  - During `Execution.request`, AshPostgres may insert `output = NULL` for queued executions.
  - The tenant DB schema previously enforced `executions.output NOT NULL`, causing inserts to fail.

  This migration allows NULL output for queued/running executions. The executor will later
  set `output` for succeeded runs.

  Notes:
  - Intended to run with `prefix` set to the tenant schema (e.g. `org_demo`).
  - Uses defensive, idempotent SQL so repeated runs won’t fail.
  """

  def up do
    # IMPORTANT:
    # Tenant migrations are executed with a `prefix()` (e.g. "org_abc"), but `current_schema()`
    # may still be "public" depending on the connection search_path. Use `prefix()` explicitly
    # so we alter the correct tenant schema every time.
    execute("""
    DO $$
    DECLARE
      schema_name text := #{inspect(prefix())};
    BEGIN
      IF schema_name IS NULL OR schema_name = '' THEN
        schema_name := current_schema();
      END IF;

      IF EXISTS (
        SELECT 1
          FROM information_schema.tables
         WHERE table_schema = schema_name
           AND table_name = 'executions'
      ) AND EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = schema_name
           AND table_name = 'executions'
           AND column_name = 'output'
      ) THEN
        -- Drop NOT NULL if currently enforced.
        IF EXISTS (
          SELECT 1
            FROM information_schema.columns
           WHERE table_schema = schema_name
             AND table_name = 'executions'
             AND column_name = 'output'
             AND is_nullable = 'NO'
        ) THEN
          EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output DROP NOT NULL', schema_name);
        END IF;

        -- Keep/restore a sensible default (safe even if output becomes nullable).
        EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output SET DEFAULT %L', schema_name, '');
      END IF;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    DECLARE
      schema_name text := #{inspect(prefix())};
    BEGIN
      IF schema_name IS NULL OR schema_name = '' THEN
        schema_name := current_schema();
      END IF;

      IF EXISTS (
        SELECT 1
          FROM information_schema.tables
         WHERE table_schema = schema_name
           AND table_name = 'executions'
      ) AND EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = schema_name
           AND table_name = 'executions'
           AND column_name = 'output'
      ) THEN
        -- Backfill NULLs before re-enforcing NOT NULL.
        EXECUTE format('UPDATE %I.executions SET output = %L WHERE output IS NULL', schema_name, '');

        -- Re-enforce NOT NULL if currently nullable.
        IF EXISTS (
          SELECT 1
            FROM information_schema.columns
           WHERE table_schema = schema_name
             AND table_name = 'executions'
             AND column_name = 'output'
             AND is_nullable = 'YES'
        ) THEN
          EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output SET NOT NULL', schema_name);
        END IF;

        EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output SET DEFAULT %L', schema_name, '');
      END IF;
    END $$;
    """)
  end
end
