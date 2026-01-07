defmodule FleetPrompt.Forums.Thread do
  @moduledoc """
  Tenant-scoped forum thread resource (Phase 2C: Forums lighthouse).

  This represents a discussion container within a category. Threads are scoped to the
  current Ash tenant (`org_<slug>`), using schema-per-tenant isolation.

  Notes / intentional constraints (Phase 2C):
  - This resource avoids compile-time references to other forum resources (e.g. `Category`)
    until they exist, to keep incremental development safe.
  - Mutations like lock/unlock should eventually be **directive-backed** (Phase 2B/2C),
    but the resource supports simple updates for now.
  """

  use Ash.Resource,
    domain: FleetPrompt.Forums,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr, only: [expr: 1]

  postgres do
    table("forum_threads")
    repo(FleetPrompt.Repo)
  end

  # Schema-per-tenant isolation: tenant is provided via Ash context
  # (e.g. `Ash.Changeset.set_tenant/2` or `tenant: "org_demo"`).
  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    # FK-like reference; relationship can be introduced once `FleetPrompt.Forums.Category` exists.
    attribute :category_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      constraints(max_length: 200)
      public?(true)
    end

    # Thread status is intentionally minimal for the lighthouse slice.
    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:open, :locked, :archived])
      default(:open)
      public?(true)
    end

    # Thread author is a user in the public schema; store the user id without a cross-schema FK.
    attribute :created_by_user_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    read :by_id do
      description("Fetch a single thread by id.")
      get?(true)

      argument :id, :uuid do
        allow_nil?(false)
      end

      filter(expr(id == ^arg(:id)))
    end

    read :by_category do
      description("List threads for a category (most recently updated first).")

      argument :category_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(category_id == ^arg(:category_id)))

      prepare(fn query, _ctx ->
        Ash.Query.sort(query, inserted_at: :desc)
      end)
    end

    create :create do
      description("Create a thread (should emit `forum.thread.created` signal at the call site).")

      accept([
        :category_id,
        :title,
        :status,
        :created_by_user_id
      ])
    end

    update :update do
      description("Update thread fields (Phase 2C; later enforce directive-backed moderation).")
      accept([:title, :status])
    end
  end

  # NOTE: Policies/authorizers are intentionally omitted for now to avoid forcing a SAT solver.
  # Route-level checks should still enforce:
  # - authenticated user
  # - org membership / tenant selection
  # - role-based moderation actions (lock/unlock/archive)

  admin do
    table_columns([:title, :status, :category_id, :created_by_user_id, :inserted_at])
  end
end
