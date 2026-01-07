defmodule FleetPrompt.Signals.Signal do
  @moduledoc """
  Tenant-scoped persisted **Signal** (Phase 2B).

  A Signal is an immutable fact (event) recorded in a tenant schema. Signals are the
  system of record for "what happened" and are intended to be:
  - durable (persisted),
  - replayable (ordered by time),
  - idempotent when a `dedupe_key` is provided.

  Notes:
  - This resource is tenant-scoped via `multitenancy :context`.
  - Updates are intentionally not exposed via actions; Signals should be append-only.
  - Do not store secrets in `payload`/`metadata`.
  """

  use Ash.Resource,
    domain: FleetPrompt.Signals,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr
  require Ash.Query

  postgres do
    table("signals")
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

    # Optional but strongly recommended for idempotency.
    # Examples:
    # - "pkg_install:org_demo:website_chat@1.0.0:installation:abc123"
    # - "webhook:stripe:event:evt_123"
    attribute :dedupe_key, :string do
      public?(true)
      constraints(max_length: 512)
    end

    # Canonical event payload (JSON-safe map). Do not put secrets here.
    attribute :payload, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    # Extra structured metadata (JSON-safe map), e.g. request ids, tags, safe headers.
    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    # Event time (may differ from insert time).
    attribute :occurred_at, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)

      default(fn ->
        DateTime.utc_now()
      end)
    end

    # Optional correlation/causation for tracing chains of events.
    attribute :correlation_id, :string do
      public?(true)
      constraints(max_length: 255)
    end

    attribute :causation_id, :string do
      public?(true)
      constraints(max_length: 255)
    end

    # Optional attribution (actor that caused the signal), tenant-safe and non-secret.
    attribute :actor_type, :string do
      public?(true)
      constraints(max_length: 64)
    end

    attribute :actor_id, :string do
      public?(true)
      constraints(max_length: 255)
    end

    # Optional subject reference (what this signal is about).
    attribute :subject_type, :string do
      public?(true)
      constraints(max_length: 64)
    end

    attribute :subject_id, :string do
      public?(true)
      constraints(max_length: 255)
    end

    # Optional signal origin (e.g. "web", "edge_connector", "oban", "system").
    attribute :source, :string do
      public?(true)
      constraints(max_length: 64)
    end

    create_timestamp(:inserted_at, type: :utc_datetime_usec, public?: true)
  end

  identities do
    # Ensure a provided dedupe key is unique per tenant.
    # IMPORTANT: avoid uniqueness conflicts for NULL keys.
    identity :unique_dedupe_key, [:dedupe_key] do
      where(expr(not is_nil(dedupe_key)))
    end
  end

  actions do
    # Intentionally omit :update/:destroy to keep the resource append-only.
    defaults([:read])

    read :by_dedupe_key do
      argument(:dedupe_key, :string, allow_nil?: false)
      get?(true)

      filter(expr(dedupe_key == ^arg(:dedupe_key)))
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

    create :emit do
      accept([
        :name,
        :dedupe_key,
        :payload,
        :metadata,
        :occurred_at,
        :correlation_id,
        :causation_id,
        :actor_type,
        :actor_id,
        :subject_type,
        :subject_id,
        :source
      ])

      # Basic guardrails
      validate(match(:name, ~r/^[a-z0-9_]+\.[a-z0-9_.]+$/))
      # `payload` is already `allow_nil?(false)`; keep validations minimal.

      change(fn changeset, _ctx ->
        # Normalize blank strings to nil for optional fields
        [
          :dedupe_key,
          :correlation_id,
          :causation_id,
          :actor_type,
          :actor_id,
          :subject_type,
          :subject_id,
          :source
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
  end

  admin do
    table_columns([
      :name,
      :dedupe_key,
      :source,
      :occurred_at,
      :inserted_at
    ])
  end
end
