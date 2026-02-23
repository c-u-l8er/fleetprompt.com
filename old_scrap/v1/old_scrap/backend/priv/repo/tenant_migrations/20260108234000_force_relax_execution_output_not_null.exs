defmodule FleetPrompt.Repo.TenantMigrations.ForceRelaxExecutionOutputNotNull do
  use Ecto.Migration

  @moduledoc """
  Tenant-scoped migration: force-relax NOT NULL constraint on `executions.output`.

  Why:
  - Some tenant schemas may have `executions.output` defined as NOT NULL.
  - Ash may insert `output = NULL` for queued/running executions depending on changes/defaults.
  - We want queued/running rows to be insertable even when output isn't known yet.

  Implementation notes:
  - Uses `prefix()` explicitly (schema-qualified DDL) instead of relying on `current_schema()`,
    because tenant migration execution/search_path can vary by environment.
  - Defensive/idempotent: safe to run multiple times.
  """

  def up do
    execute("""
    DO $$
    DECLARE
      schema_name text := '#{prefix()}';
      is_nullable text;
    BEGIN
      IF schema_name IS NULL OR schema_name = '' THEN
        schema_name := current_schema();
      END IF;

      -- Only proceed if the tenant has an executions table and output column.
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
        SELECT c.is_nullable
          INTO is_nullable
          FROM information_schema.columns c
         WHERE c.table_schema = schema_name
           AND c.table_name = 'executions'
           AND c.column_name = 'output';

        -- Drop NOT NULL if enforced.
        IF is_nullable = 'NO' THEN
          EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output DROP NOT NULL', schema_name);
        END IF;

        -- Ensure a sensible default remains.
        EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output SET DEFAULT %L', schema_name, '');
      END IF;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    DECLARE
      schema_name text := '#{prefix()}';
      is_nullable text;
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
        -- Backfill before re-enforcing NOT NULL.
        EXECUTE format('UPDATE %I.executions SET output = %L WHERE output IS NULL', schema_name, '');

        SELECT c.is_nullable
          INTO is_nullable
          FROM information_schema.columns c
         WHERE c.table_schema = schema_name
           AND c.table_name = 'executions'
           AND c.column_name = 'output';

        -- Re-enforce NOT NULL if currently nullable.
        IF is_nullable = 'YES' THEN
          EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output SET NOT NULL', schema_name);
        END IF;

        EXECUTE format('ALTER TABLE %I.executions ALTER COLUMN output SET DEFAULT %L', schema_name, '');
      END IF;
    END $$;
    """)
  end
end
