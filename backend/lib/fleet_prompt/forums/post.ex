defmodule FleetPrompt.Forums.Post do
  @moduledoc """
  Tenant-scoped forum post.

  Phase 2C (Forums-first lighthouse) requirements:
  - Posts live in the tenant schema (e.g. `org_demo`) using `multitenancy :context`.
  - Posts are durable product data; relevant actions should emit Signals (via `FleetPrompt.Signals.SignalBus`)
    and moderation changes should be directive-backed (Phase 2B), but that wiring is handled by
    controllers/services/jobs, not directly inside this resource.

  Design notes:
  - `thread_id` is stored as a UUID attribute (not an Ash relationship) to avoid compile-time
    coupling while the forum domain is being built incrementally.
  - `author_id` is a string because authors may be humans (UUID user id), agents, or system actors
    that may not have a tenant-local FK.
  """

  use Ash.Resource,
    domain: FleetPrompt.Forums,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr, only: [expr: 1]

  postgres do
    table("forum_posts")
    repo(FleetPrompt.Repo)
  end

  # Schema-per-tenant isolation: tenant is provided via Ash context (e.g. `Ash.Changeset.set_tenant/2`)
  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :thread_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      allow_nil?(false)
      public?(true)

      constraints(
        min_length: 1,
        max_length: 20_000
      )
    end

    attribute :status, :atom do
      allow_nil?(false)
      public?(true)

      constraints(one_of: [:published, :hidden, :deleted])
      default(:published)
    end

    attribute :author_type, :atom do
      allow_nil?(false)
      public?(true)

      constraints(one_of: [:human, :agent, :system])
      default(:human)
    end

    attribute :author_id, :string do
      allow_nil?(false)
      public?(true)
    end

    # Optional, JSON-safe details (do not store secrets)
    attribute :metadata, :map do
      public?(true)
      default(%{})
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    read :by_thread do
      argument :thread_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(thread_id == ^arg(:thread_id)))
    end

    create :create do
      accept([:thread_id, :content, :author_type, :author_id, :metadata])

      change(fn changeset, _ctx ->
        # Enforce that a "created" post always starts as published.
        # Moderation transitions (hide/delete) should be directive-backed.
        Ash.Changeset.force_change_attribute(changeset, :status, :published)
      end)
    end

    update :edit do
      accept([:content])

      # Editing content is allowed as a direct update for now.
      # If you want edits to be directive-backed, add directive wiring at the controller/service layer.
    end

    update :hide do
      require_atomic?(false)

      accept([])

      change(fn changeset, _ctx ->
        Ash.Changeset.force_change_attribute(changeset, :status, :hidden)
      end)
    end

    update :unhide do
      require_atomic?(false)

      accept([])

      change(fn changeset, _ctx ->
        Ash.Changeset.force_change_attribute(changeset, :status, :published)
      end)
    end

    update :delete do
      require_atomic?(false)

      accept([])

      change(fn changeset, _ctx ->
        # Soft-delete semantics.
        Ash.Changeset.force_change_attribute(changeset, :status, :deleted)
      end)
    end
  end

  admin do
    table_columns([:thread_id, :status, :author_type, :author_id, :inserted_at])
  end
end
