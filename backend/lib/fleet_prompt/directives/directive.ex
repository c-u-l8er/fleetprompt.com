defmodule FleetPrompt.Directives.Directive do
  @moduledoc """
  Tenant-scoped persisted **Directive** (Phase 2B).

  A Directive is an auditable command (controlled intent) that represents the
  *only allowed path* to side effects.

  Key properties:
  - tenant-scoped via `multitenancy :context`
  - idempotent when `idempotency_key` is provided (recommended)
  - durable lifecycle state machine (`:requested` -> `:running` -> `:succeeded` / `:failed`)
  - stores parameters as JSON-safe maps (`payload`, `metadata`, `result`)

  Security note:
  - Do **not** store secrets in `payload` or `metadata`. Use an encrypted secrets
    store for credentials (out of scope for this slice).
  """

  use Ash.Resource,
    domain: FleetPrompt.Directives,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr
  require Ash.Query

  postgres do
    table("directives")
    repo(FleetPrompt.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 255)
    end

    # Optional but strongly recommended for idempotency and retry safety.
    # Examples:
    # - "package.install:org_demo:website_chat@1.0.0"
    # - "webchat.mm_escalation:org_demo:conversation:abc123:channel:ops"
    attribute :idempotency_key, :string do
      public?(true)
      constraints(max_length: 512)
    end

    # Directive lifecycle
    attribute :status, :atom do
      allow_nil?(false)

      constraints(
        one_of: [
          :requested,
          :running,
          :succeeded,
          :failed,
          :canceled
        ]
      )

      default(:requested)
      public?(true)
    end

    # Desired execution time (scheduler/runner may pick it up later).
    attribute :scheduled_at, :utc_datetime_usec do
      public?(true)

      default(fn ->
        DateTime.utc_now()
      end)
    end

    attribute :started_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :completed_at, :utc_datetime_usec do
      public?(true)
    end

    # JSON-safe directive parameters. Do not store secrets here.
    attribute :payload, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    # Structured metadata for tracing/ops (request ids, safe headers, tags, etc.).
    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    # Optional result payload for successful executions (JSON-safe).
    attribute :result, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    # Operational error details (best-effort, safe string)
    attribute :last_error, :string do
      public?(true)
    end

    attribute :last_error_at, :utc_datetime_usec do
      public?(true)
    end

    # Optional attribution (who requested the directive).
    # NOTE: this is a public-schema user UUID; we avoid cross-schema FKs.
    attribute :requested_by_user_id, :uuid do
      public?(true)
    end

    # Retry counters (for a future runner/job integration)
    attribute :attempt, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :max_attempts, :integer do
      allow_nil?(false)
      default(10)
      public?(true)
    end

    timestamps()
  end

  identities do
    # Enforce idempotency when an idempotency key is present.
    #
    # Postgres unique indexes allow multiple NULL values, so we do not need a
    # partial unique index here. Keeping this as a plain identity avoids
    # requiring `postgres.identity_wheres_to_sql` mapping during migration generation.
    identity(:unique_idempotency_key, [:idempotency_key])
  end

  actions do
    # Intentionally omit default :update to force explicit lifecycle transitions.
    # We allow :read for visibility and :destroy is intentionally omitted (auditability).
    defaults([:read])

    read :by_idempotency_key do
      argument(:idempotency_key, :string, allow_nil?: false)
      get?(true)

      filter(expr(idempotency_key == ^arg(:idempotency_key)))
    end

    read :recent do
      argument(:limit, :integer, allow_nil?: true, default: 50)

      prepare(fn query, ctx ->
        limit = (ctx.arguments[:limit] || 50) |> min(500) |> max(1)

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end)
    end

    create :request do
      accept([
        :name,
        :idempotency_key,
        :payload,
        :metadata,
        :scheduled_at,
        :requested_by_user_id,
        :max_attempts
      ])

      validate(match(:name, ~r/^[a-z0-9_]+\.[a-z0-9_.]+$/))

      change(set_attribute(:status, :requested))
      change(set_attribute(:attempt, 0))
      change(set_attribute(:started_at, nil))
      change(set_attribute(:completed_at, nil))
      change(set_attribute(:last_error, nil))
      change(set_attribute(:last_error_at, nil))
      change(set_attribute(:result, %{}))

      change(fn changeset, _ctx ->
        # Normalize blank strings to nil for optional fields
        [
          :idempotency_key
        ]
        |> Enum.reduce(changeset, fn attr, cs ->
          val = Ash.Changeset.get_attribute(cs, attr)

          if is_binary(val) and String.trim(val) == "" do
            Ash.Changeset.force_change_attribute(cs, attr, nil)
          else
            cs
          end
        end)
      end)
    end

    update :mark_running do
      require_atomic?(false)

      accept([])

      change(fn changeset, _ctx ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :running)
        |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:last_error, nil)
        |> Ash.Changeset.force_change_attribute(:last_error_at, nil)
      end)
    end

    update :mark_succeeded do
      require_atomic?(false)

      argument(:result, :map, allow_nil?: true)
      accept([])

      change(fn changeset, _ctx ->
        result =
          case Ash.Changeset.get_argument(changeset, :result) do
            %{} = r -> r
            _ -> %{}
          end

        changeset
        |> Ash.Changeset.force_change_attribute(:status, :succeeded)
        |> Ash.Changeset.force_change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:result, result)
        |> Ash.Changeset.force_change_attribute(:last_error, nil)
        |> Ash.Changeset.force_change_attribute(:last_error_at, nil)
      end)
    end

    update :mark_failed do
      require_atomic?(false)

      argument(:error, :string, allow_nil?: false)
      accept([])

      change(fn changeset, _ctx ->
        error =
          case Ash.Changeset.get_argument(changeset, :error) do
            e when is_binary(e) ->
              case String.trim(e) do
                "" -> "Directive failed"
                trimmed -> trimmed
              end

            _ ->
              "Directive failed"
          end

        changeset
        |> Ash.Changeset.force_change_attribute(:status, :failed)
        |> Ash.Changeset.force_change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:last_error, error)
        |> Ash.Changeset.force_change_attribute(:last_error_at, DateTime.utc_now())
      end)
    end

    update :cancel do
      require_atomic?(false)
      accept([])

      change(fn changeset, _ctx ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :canceled)
        |> Ash.Changeset.force_change_attribute(:completed_at, DateTime.utc_now())
      end)
    end

    update :bump_attempt do
      # Increment attempt counter for a future runner.
      #
      # This action is intentionally lightweight; a proper runner should enforce:
      # - max attempts
      # - backoff policy
      # - idempotent execution semantics
      require_atomic?(false)
      accept([])

      change(fn changeset, _ctx ->
        current = changeset.data.attempt || 0
        Ash.Changeset.force_change_attribute(changeset, :attempt, current + 1)
      end)
    end
  end

  calculations do
    calculate(:is_terminal, :boolean, expr(status in [:succeeded, :failed, :canceled]))
    calculate(:is_pending, :boolean, expr(status in [:requested, :running]))
  end

  admin do
    table_columns([
      :name,
      :status,
      :idempotency_key,
      :attempt,
      :max_attempts,
      :scheduled_at,
      :started_at,
      :completed_at,
      :inserted_at
    ])
  end
end
