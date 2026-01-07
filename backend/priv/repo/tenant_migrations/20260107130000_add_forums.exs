defmodule FleetPrompt.Repo.TenantMigrations.AddForums do
  @moduledoc """
  Tenant migration: add forums tables.

  Creates tenant-scoped tables (in each `org_<slug>` schema via `prefix()`):
  - `forum_categories`
  - `forum_threads`
  - `forum_posts`

  Notes:
  - Uses `public.gen_random_uuid()` to avoid UUID default resolution issues in tenant schemas.
  - Uses JSONB defaults via `'{}'::jsonb`.
  - Avoids cross-schema foreign keys; references to public-schema users are stored as UUIDs without FKs.
  - Keeps relationships (`category_id`, `thread_id`) as UUID columns without FK constraints to keep
    tenant migrations resilient and easy to evolve.
  """

  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"")

    # -----------------------
    # forum_categories
    # -----------------------
    create_if_not_exists table(:forum_categories, primary_key: false, prefix: prefix()) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(:slug, :text, null: false)
      add(:name, :text, null: false)
      add(:description, :text)
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

    create_if_not_exists(
      unique_index(:forum_categories, [:slug],
        name: "forum_categories_unique_slug_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:forum_categories, [:status],
        name: "forum_categories_status_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:forum_categories, [:inserted_at],
        name: "forum_categories_inserted_at_index",
        prefix: prefix()
      )
    )

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_categories_slug_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_categories
          ADD CONSTRAINT forum_categories_slug_nonempty_check
          CHECK (char_length(slug) > 0);
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_categories_name_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_categories
          ADD CONSTRAINT forum_categories_name_nonempty_check
          CHECK (char_length(name) > 0);
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_categories_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_categories
          ADD CONSTRAINT forum_categories_status_check
          CHECK (status IN ('active','archived'));
      END IF;
    END $$;
    """)

    # -----------------------
    # forum_threads
    # -----------------------
    create_if_not_exists table(:forum_threads, primary_key: false, prefix: prefix()) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(:category_id, :uuid, null: false)
      add(:title, :text, null: false)
      add(:status, :text, null: false, default: "open")

      # Public-schema user UUID (no FK across schemas)
      add(:created_by_user_id, :uuid, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create_if_not_exists(
      index(:forum_threads, [:category_id],
        name: "forum_threads_category_id_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:forum_threads, [:status],
        name: "forum_threads_status_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:forum_threads, [:inserted_at],
        name: "forum_threads_inserted_at_index",
        prefix: prefix()
      )
    )

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_threads_title_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_threads
          ADD CONSTRAINT forum_threads_title_nonempty_check
          CHECK (char_length(title) > 0);
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_threads_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_threads
          ADD CONSTRAINT forum_threads_status_check
          CHECK (status IN ('open','locked','archived'));
      END IF;
    END $$;
    """)

    # -----------------------
    # forum_posts
    # -----------------------
    create_if_not_exists table(:forum_posts, primary_key: false, prefix: prefix()) do
      add(:id, :uuid,
        null: false,
        default: fragment("public.gen_random_uuid()"),
        primary_key: true
      )

      add(:thread_id, :uuid, null: false)
      add(:content, :text, null: false)

      add(:status, :text, null: false, default: "published")
      add(:author_type, :text, null: false, default: "human")
      add(:author_id, :text, null: false)

      add(:metadata, :map, null: false, default: fragment("'{}'::jsonb"))

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create_if_not_exists(
      index(:forum_posts, [:thread_id],
        name: "forum_posts_thread_id_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:forum_posts, [:status],
        name: "forum_posts_status_index",
        prefix: prefix()
      )
    )

    create_if_not_exists(
      index(:forum_posts, [:inserted_at],
        name: "forum_posts_inserted_at_index",
        prefix: prefix()
      )
    )

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_posts_content_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts
          ADD CONSTRAINT forum_posts_content_nonempty_check
          CHECK (char_length(content) > 0);
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_posts_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts
          ADD CONSTRAINT forum_posts_status_check
          CHECK (status IN ('published','hidden','deleted'));
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_posts_author_type_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts
          ADD CONSTRAINT forum_posts_author_type_check
          CHECK (author_type IN ('human','agent','system'));
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'forum_posts_author_id_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts
          ADD CONSTRAINT forum_posts_author_id_nonempty_check
          CHECK (char_length(author_id) > 0);
      END IF;
    END $$;
    """)
  end

  def down do
    # Drop constraints (best-effort, idempotent)
    execute("""
    DO $$
    BEGIN
      -- forum_posts
      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_posts_author_id_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts DROP CONSTRAINT forum_posts_author_id_nonempty_check;
      END IF;

      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_posts_author_type_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts DROP CONSTRAINT forum_posts_author_type_check;
      END IF;

      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_posts_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts DROP CONSTRAINT forum_posts_status_check;
      END IF;

      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_posts_content_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_posts DROP CONSTRAINT forum_posts_content_nonempty_check;
      END IF;

      -- forum_threads
      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_threads_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_threads DROP CONSTRAINT forum_threads_status_check;
      END IF;

      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_threads_title_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_threads DROP CONSTRAINT forum_threads_title_nonempty_check;
      END IF;

      -- forum_categories
      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_categories_status_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_categories DROP CONSTRAINT forum_categories_status_check;
      END IF;

      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_categories_name_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_categories DROP CONSTRAINT forum_categories_name_nonempty_check;
      END IF;

      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'forum_categories_slug_nonempty_check'
          AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix()}')
      ) THEN
        ALTER TABLE "#{prefix()}".forum_categories DROP CONSTRAINT forum_categories_slug_nonempty_check;
      END IF;
    END $$;
    """)

    # Drop indexes (idempotent)
    drop_if_exists(
      index(:forum_posts, [:inserted_at],
        name: "forum_posts_inserted_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_posts, [:status],
        name: "forum_posts_status_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_posts, [:thread_id],
        name: "forum_posts_thread_id_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_threads, [:inserted_at],
        name: "forum_threads_inserted_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_threads, [:status],
        name: "forum_threads_status_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_threads, [:category_id],
        name: "forum_threads_category_id_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_categories, [:inserted_at],
        name: "forum_categories_inserted_at_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      index(:forum_categories, [:status],
        name: "forum_categories_status_index",
        prefix: prefix()
      )
    )

    drop_if_exists(
      unique_index(:forum_categories, [:slug],
        name: "forum_categories_unique_slug_index",
        prefix: prefix()
      )
    )

    # Drop tables (idempotent)
    drop_if_exists(table(:forum_posts, prefix: prefix()))
    drop_if_exists(table(:forum_threads, prefix: prefix()))
    drop_if_exists(table(:forum_categories, prefix: prefix()))
  end
end
