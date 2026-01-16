defmodule FleetPrompt.Agents.ExecutionLog do
  @moduledoc """
  Tenant-scoped execution logs.

  This resource is the durable, queryable log stream for an agent "run" (execution).
  It is intentionally simple and JSON-safe:

  - `execution_id` ties the log entry to a specific execution record (UUID).
  - `level` is an atom enum (e.g. :debug/:info/:warning/:error).
  - `message` is the human-readable log line.
  - `data` is optional structured metadata (map / JSON).
  - `occurred_at` allows callers (jobs, controllers) to attach a precise timestamp;
    defaults to `DateTime.utc_now/0` when omitted.

  Notes:
  - This is tenant-scoped via `multitenancy :context` (schema-per-tenant).
  - This resource does not enforce authorization/policies yet (consistent with current codebase stance).
  """

  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshAdmin.Resource
    ]

  postgres do
    table("execution_logs")
    repo(FleetPrompt.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    # Foreign key reference (UUID) to the execution record for this tenant.
    #
    # We keep this as a plain UUID attribute (not a relationship) to avoid
    # hard coupling to an Execution resource/module until it exists in-code.
    attribute :execution_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :level, :atom do
      allow_nil?(false)
      constraints(one_of: [:debug, :info, :warning, :error])
      default(:info)
      public?(true)
    end

    attribute :message, :string do
      allow_nil?(false)
      public?(true)
    end

    # JSON-safe structured metadata (never store secrets here).
    attribute :data, :map do
      default(%{})
      public?(true)
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil?(false)
      default(&DateTime.utc_now/0)
      public?(true)
    end

    timestamps()
  end

  identities do
    # Fast lookup for "all logs for an execution", and a basic guardrail against
    # accidental duplicate inserts if callers retry with the same `occurred_at`.
    #
    # NOTE: This is not a perfect idempotency key; callers that need strict
    # idempotency should provide a deterministic `occurred_at` or add an explicit
    # idempotency key field in a future iteration.
    identity :unique_execution_log, [:execution_id, :occurred_at, :message]
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:execution_id, :level, :message, :data, :occurred_at])
    end

    # Convenience action: read logs for a specific execution.
    read :by_execution do
      argument :execution_id, :uuid do
        allow_nil?(false)
      end

      # NOTE: Ash expression DSL is available here; this is a simple equality filter.
      filter(expr(execution_id == ^arg(:execution_id)))

      # Default ordering: chronological.
      prepare(build(sort: [occurred_at: :asc, inserted_at: :asc]))
    end
  end

  admin do
    table_columns([:execution_id, :level, :message, :occurred_at, :inserted_at])
  end
end
