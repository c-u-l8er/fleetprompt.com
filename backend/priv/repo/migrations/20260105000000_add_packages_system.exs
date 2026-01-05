defmodule FleetPrompt.Repo.Migrations.AddPackagesSystem do
  use Ecto.Migration

  def change do
    # Packages (global / public schema)
    create table(:packages, primary_key: false) do
      add(:id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()"))

      add(:name, :text, null: false)
      add(:slug, :text, null: false)
      add(:version, :text, null: false)

      add(:description, :text)
      add(:long_description, :text)

      # Ash `:atom` attributes are stored as text in Postgres
      add(:category, :text)

      # Publisher metadata
      add(:author, :text)
      add(:author_url, :text)
      add(:repository_url, :text)
      add(:documentation_url, :text)
      add(:license, :text, null: false, default: "MIT")
      add(:icon_url, :text)

      # Pricing
      add(:pricing_model, :text, null: false, default: "free")
      add(:pricing_config, :map, null: false, default: fragment("'{}'::jsonb"))

      # Requirements
      add(:min_fleet_prompt_tier, :text, null: false, default: "free")
      add(:dependencies, {:array, :map}, null: false, default: [])

      # Registry pointers (optional for now)
      add(:package_url, :text)
      add(:checksum, :text)

      # Display + install planning
      add(:includes, :map,
        null: false,
        default: fragment("'{\"agents\":[],\"workflows\":[],\"skills\":[],\"tools\":[]}'::jsonb")
      )

      # Stats
      add(:install_count, :bigint, null: false, default: 0)
      add(:active_install_count, :bigint, null: false, default: 0)
      add(:rating_avg, :decimal)
      add(:rating_count, :bigint, null: false, default: 0)

      # Flags
      add(:is_verified, :boolean, null: false, default: false)
      add(:is_featured, :boolean, null: false, default: false)
      add(:is_published, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:packages, [:slug], name: "packages_unique_slug_index"))
    create(unique_index(:packages, [:name, :version], name: "packages_unique_name_version_index"))

    create(index(:packages, [:is_published], name: "packages_is_published_index"))
    create(index(:packages, [:is_featured], name: "packages_is_featured_index"))
    create(index(:packages, [:install_count], name: "packages_install_count_index"))
    create(index(:packages, [:category], name: "packages_category_index"))
    create(index(:packages, [:pricing_model], name: "packages_pricing_model_index"))
    create(index(:packages, [:min_fleet_prompt_tier], name: "packages_min_tier_index"))

    create(
      constraint(:packages, :packages_category_check,
        check:
          "category IS NULL OR category IN ('operations','customer_service','sales','data','development','marketing','finance','hr')"
      )
    )

    create(
      constraint(:packages, :packages_pricing_model_check,
        check: "pricing_model IN ('free','freemium','paid','revenue_share')"
      )
    )

    create(
      constraint(:packages, :packages_min_tier_check,
        check: "min_fleet_prompt_tier IN ('free','pro','enterprise')"
      )
    )

    # Package reviews (global / public schema)
    create table(:package_reviews, primary_key: false) do
      add(:id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()"))

      add(:package_id, :uuid, null: false)
      add(:user_id, :uuid, null: false)

      add(:rating, :integer, null: false)
      add(:title, :text)
      add(:content, :text)
      add(:helpful_count, :bigint, null: false, default: 0)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:package_reviews, [:package_id], name: "package_reviews_package_id_index"))
    create(index(:package_reviews, [:user_id], name: "package_reviews_user_id_index"))

    create(
      unique_index(:package_reviews, [:package_id, :user_id],
        name: "package_reviews_unique_package_user_index"
      )
    )

    create(
      constraint(:package_reviews, :package_reviews_rating_check,
        check: "rating >= 1 AND rating <= 5"
      )
    )
  end
end
