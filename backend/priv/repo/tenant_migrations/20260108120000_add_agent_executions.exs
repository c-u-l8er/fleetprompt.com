defmodule FleetPrompt.Repo.TenantMigrations.AddAgentExecutions do
  use Ecto.Migration

  @moduledoc """
  Tenant-scoped migration: align DB schema for `executions` and `execution_logs`
  with the Ash resources:

  - `FleetPrompt.Agents.Execution`  (table: `executions`)
  - `FleetPrompt.Agents.ExecutionLog` (table: `execution_logs`)

  Notes:
  - This migration is intended to run with `prefix` set to a tenant schema (e.g. `org_demo`).
  - UUID defaults are schema-qualified (`public.gen_random_uuid()`) to avoid tenant extension drift.
  - Where possible, we use `*_if_not_exists` helpers to keep tenant migrations idempotent.
  - If earlier dev iterations created an `executions` table with different columns, we do
    best-effort reconciliation (rename `status` -> `state`, backfill `finished_at` from `completed_at`,
    coerce `input` to text if it was created as jsonb, etc.). Extra columns are left in place.
  """

  def up do
    # ----
    # executions
    # ----
    create_if_not_exists table(:executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("public.gen_random_uuid()")

      add :agent_id,
          references(:agents, type: :uuid, on_delete: :delete_all),
          null: false

      # Matches Execution resource attributes (Ash atom fields are stored as strings in Postgres).
      add :state, :string, null: false, default: "queued"

      add :model, :string, null: false, default: "openrouter/anthropic/claude-3.5-sonnet"
      add :temperature, :float, null: false, default: 0.7
      add :max_tokens, :integer, null: false, default: 1024

      add :input, :text, null: false
      add :request, :map, null: false, default: fragment("'{}'::jsonb")

      add :output, :text, null: false, default: ""
      add :error, :text

      add :prompt_tokens, :integer, null: false, default: 0
      add :completion_tokens, :integer, null: false, default: 0
      add :total_tokens, :integer, null: false, default: 0

      add :cost_cents, :integer

      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:executions, [:agent_id])
    create_if_not_exists index(:executions, [:state])
    create_if_not_exists index(:executions, [:inserted_at])

    # Best-effort reconciliation for older schemas (dev iterations).
    execute("""
    DO $$
    BEGIN
      -- If an older schema used `status` instead of `state`, rename it.
      IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'status'
      ) AND NOT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'state'
      ) THEN
        EXECUTE 'ALTER TABLE executions RENAME COLUMN status TO state';
      END IF;

      -- If an older schema created `input` as jsonb/map, coerce it to text.
      IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'input'
           AND (udt_name = 'jsonb' OR data_type = 'json')
      ) THEN
        EXECUTE 'ALTER TABLE executions ALTER COLUMN input TYPE text USING input::text';
      END IF;

      -- If an older schema used `completed_at`, backfill `finished_at` when possible.
      IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'completed_at'
      ) AND EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'finished_at'
      ) THEN
        EXECUTE 'UPDATE executions SET finished_at = completed_at WHERE finished_at IS NULL AND completed_at IS NOT NULL';
      END IF;

      -- Ensure defaults are sane (safe to run repeatedly).
      IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'state'
      ) THEN
        EXECUTE 'ALTER TABLE executions ALTER COLUMN state SET DEFAULT ''queued''';
      END IF;

      IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = 'executions'
           AND column_name = 'output'
      ) THEN
        EXECUTE 'ALTER TABLE executions ALTER COLUMN output SET DEFAULT ''''';
      END IF;
    END $$;
    """)

    # ----
    # execution_logs
    # ----
    create_if_not_exists table(:execution_logs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("public.gen_random_uuid()")

      add :execution_id,
          references(:executions, type: :uuid, on_delete: :delete_all),
          null: false

      add :level, :string, null: false, default: "info"
      add :message, :text, null: false
      add :data, :map, null: false, default: fragment("'{}'::jsonb")

      add :occurred_at, :utc_datetime_usec, null: false, default: fragment("now()")

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:execution_logs, [:execution_id])
    create_if_not_exists index(:execution_logs, [:occurred_at])
    create_if_not_exists index(:execution_logs, [:level])

    # Identity alignment for `FleetPrompt.Agents.ExecutionLog`:
    # identity :unique_execution_log, [:execution_id, :occurred_at, :message]
    create_if_not_exists index(:execution_logs, [:execution_id, :occurred_at, :message],
                           unique: true,
                           name: :execution_logs_exec_occ_msg_uniq
                         )

    # Best-effort reconciliation for older schemas that created logs without occurred_at / updated_at.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
          FROM information_schema.tables
         WHERE table_schema = current_schema()
           AND table_name = 'execution_logs'
      ) THEN
        IF NOT EXISTS (
          SELECT 1
            FROM information_schema.columns
           WHERE table_schema = current_schema()
             AND table_name = 'execution_logs'
             AND column_name = 'occurred_at'
        ) THEN
          EXECUTE 'ALTER TABLE execution_logs ADD COLUMN occurred_at timestamptz NOT NULL DEFAULT now()';
        END IF;

        IF NOT EXISTS (
          SELECT 1
            FROM information_schema.columns
           WHERE table_schema = current_schema()
             AND table_name = 'execution_logs'
             AND column_name = 'updated_at'
        ) THEN
          EXECUTE 'ALTER TABLE execution_logs ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now()';
        END IF;

        IF NOT EXISTS (
          SELECT 1
            FROM information_schema.columns
           WHERE table_schema = current_schema()
             AND table_name = 'execution_logs'
             AND column_name = 'inserted_at'
        ) THEN
          EXECUTE 'ALTER TABLE execution_logs ADD COLUMN inserted_at timestamptz NOT NULL DEFAULT now()';
        END IF;
      END IF;
    END $$;
    """)
  end

  def down do
    drop_if_exists index(:execution_logs, [:execution_id, :occurred_at, :message],
                     name: :execution_logs_exec_occ_msg_uniq
                   )

    drop_if_exists index(:execution_logs, [:level])
    drop_if_exists index(:execution_logs, [:occurred_at])
    drop_if_exists index(:execution_logs, [:execution_id])
    drop_if_exists table(:execution_logs)

    drop_if_exists index(:executions, [:inserted_at])
    drop_if_exists index(:executions, [:state])
    drop_if_exists index(:executions, [:agent_id])
    drop_if_exists table(:executions)
  end
end
