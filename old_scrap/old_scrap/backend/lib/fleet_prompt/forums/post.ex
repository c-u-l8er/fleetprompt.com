
defmodule FleetPrompt.Forums.Post do
  @moduledoc """
  Tenant-scoped forum post resource.
  """

  use Ash.Resource,
    domain: FleetPrompt.Forums,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr, only: [expr: 1, arg: 1]

  postgres do
    table "forum_posts"
    repo FleetPrompt.Repo
  end

  multitenancy do
    strategy :context
  end

  attributes do
    uuid_primary_key :id

    attribute :thread_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? false
      public? true
      constraints(
        min_length: 1,
        max_length: 20_000
      )
    end

    attribute :status, :atom do
      constraints [one_of: [:published, :hidden, :deleted]]
      default :published
      allow_nil? false
      public? true
    end

    attribute :author_type, :atom do
      constraints [one_of: [:human, :agent, :system]]
      default :human
      allow_nil? false
      public? true
    end

    attribute :author_id, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:thread_id, :content, :status, :author_type, :author_id]
    end

    update :update do
      accept [:content, :status]
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

    read :by_id do
      argument :id, :uuid do
        allow_nil? false
      end

      get? true
      filter expr(id == ^arg(:id))
    end

    read :by_thread do
      argument :thread_id, :uuid do
        allow_nil? false
      end
      filter expr(thread_id == ^arg(:thread_id))
      prepare build(sort: [inserted_at: :asc])
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
    table_columns([:thread_id, :content, :status, :author_type, :author_id, :inserted_at])
  end
end
