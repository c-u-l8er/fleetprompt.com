defmodule FleetPrompt.Packages.Review do
  @moduledoc """
  Package review + rating resource.

  Notes:
  - Reviews are stored in the **public** schema (global), not per-tenant.
  - This resource intentionally uses `package_id` as a UUID reference (not an Ash relationship)
    so it can compile safely before Phase 2 introduces `FleetPrompt.Packages.Package`.
    Once `FleetPrompt.Packages.Package` exists, we can upgrade this to a real `belongs_to :package`
    relationship if desired.
  """

  use Ash.Resource,
    domain: FleetPrompt.Packages,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table("package_reviews")
    repo(FleetPrompt.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :package_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :user_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :rating, :integer do
      allow_nil?(false)
      constraints(min: 1, max: 5)
      public?(true)
    end

    attribute :title, :string do
      public?(true)
    end

    attribute :content, :string do
      public?(true)
    end

    attribute :helpful_count, :integer do
      default(0)
      public?(true)
    end

    timestamps()
  end

  identities do
    # A user should only be able to leave one review per package.
    identity(:unique_review_per_user_per_package, [:package_id, :user_id])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:package_id, :user_id, :rating, :title, :content])
    end

    update :update do
      accept([:rating, :title, :content])
    end

    update :mark_helpful do
      require_atomic?(false)

      change(fn changeset, _context ->
        current = (changeset.data.helpful_count || 0) + 1
        Ash.Changeset.force_change_attribute(changeset, :helpful_count, current)
      end)
    end
  end

  admin do
    table_columns([:package_id, :user_id, :rating, :helpful_count, :inserted_at])
  end
end
