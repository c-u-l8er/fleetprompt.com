defmodule FleetPrompt.Repo.Migrations.AddOrganizationMemberships do
  use Ecto.Migration

  def up do
    create table(:organization_memberships, primary_key: false) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(
        :organization_id,
        references(:organizations,
          column: :id,
          type: :uuid,
          prefix: "public",
          on_delete: :delete_all
        ),
        null: false
      )

      add(
        :user_id,
        references(:users,
          column: :id,
          type: :uuid,
          prefix: "public",
          on_delete: :delete_all
        ),
        null: false
      )

      # Membership role within the org.
      # Keep as text to align with existing role storage patterns in this repo.
      add(:role, :text, null: false, default: "member")

      # Membership lifecycle status (active users can access the org/tenant)
      add(:status, :text, null: false, default: "active")

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create(
      unique_index(:organization_memberships, [:organization_id, :user_id],
        name: "organization_memberships_unique_org_user_index"
      )
    )

    create(
      index(:organization_memberships, [:organization_id],
        name: "organization_memberships_organization_id_index"
      )
    )

    create(
      index(:organization_memberships, [:user_id], name: "organization_memberships_user_id_index")
    )

    create(index(:organization_memberships, [:role], name: "organization_memberships_role_index"))

    create(
      index(:organization_memberships, [:status], name: "organization_memberships_status_index")
    )
  end

  def down do
    drop_if_exists(
      index(:organization_memberships, [:status], name: "organization_memberships_status_index")
    )

    drop_if_exists(
      index(:organization_memberships, [:role], name: "organization_memberships_role_index")
    )

    drop_if_exists(
      index(:organization_memberships, [:user_id], name: "organization_memberships_user_id_index")
    )

    drop_if_exists(
      index(:organization_memberships, [:organization_id],
        name: "organization_memberships_organization_id_index"
      )
    )

    drop_if_exists(
      unique_index(:organization_memberships, [:organization_id, :user_id],
        name: "organization_memberships_unique_org_user_index"
      )
    )

    drop(table(:organization_memberships))
  end
end
