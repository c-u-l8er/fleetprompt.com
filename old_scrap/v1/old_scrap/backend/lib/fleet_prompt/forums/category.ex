defmodule FleetPrompt.Forums.Category do
  @moduledoc """
  Tenant-scoped forum category.

  Phase 2C (Forums lighthouse):
  - Categories live in the tenant schema (`org_<slug>`) via `multitenancy :context`.
  - This is intentionally minimal: enough to back `/forums` and `/forums/c/:slug`,
    and to support "create category" from the UI.

  Notes:
  - Authorization/policies are intentionally deferred (same stance as other resources).
  - Signal emission (`forum.category.created`) should be performed by the write
    entrypoint (controller/service) using `FleetPrompt.Signals.SignalBus`.
  """

  use Ash.Resource,
    domain: FleetPrompt.Forums,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr, only: [expr: 1, arg: 1]

  postgres do
    table("forum_categories")
    repo(FleetPrompt.Repo)
  end

  # Schema-per-tenant isolation: tenant is provided via Ash context (e.g. `Ash.Changeset.set_tenant/2`)
  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:active, :archived])
      default(:active)
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:slug, :name, :description, :status])

      change(fn changeset, _context ->
        slug = changeset |> Ash.Changeset.get_attribute(:slug) |> normalize_slug()
        name = changeset |> Ash.Changeset.get_attribute(:name) |> normalize_string()
        description = changeset |> Ash.Changeset.get_attribute(:description) |> normalize_string()

        changeset
        |> Ash.Changeset.force_change_attribute(:slug, slug)
        |> Ash.Changeset.force_change_attribute(:name, name)
        |> Ash.Changeset.force_change_attribute(:description, blank_to_nil(description))
        |> validate_slug_format()
      end)
    end

    update :update do
      accept([:slug, :name, :description, :status])
      require_atomic?(false)

      change(fn changeset, _context ->
        slug = changeset |> Ash.Changeset.get_attribute(:slug) |> normalize_slug()
        name = changeset |> Ash.Changeset.get_attribute(:name) |> normalize_string()
        description = changeset |> Ash.Changeset.get_attribute(:description) |> normalize_string()

        changeset
        |> Ash.Changeset.force_change_attribute(:slug, slug)
        |> Ash.Changeset.force_change_attribute(:name, name)
        |> Ash.Changeset.force_change_attribute(:description, blank_to_nil(description))
        |> validate_slug_format()
      end)
    end

    read :by_id do
      get?(true)

      argument :id, :uuid do
        allow_nil?(false)
      end

      filter(expr(id == ^arg(:id)))
    end

    read :by_slug do
      argument :slug, :string do
        allow_nil?(false)
      end

      filter(expr(slug == ^arg(:slug)))
    end
  end

  admin do
    table_columns([:name, :slug, :status, :inserted_at])
  end

  # -----------------------
  # Internal helpers
  # -----------------------

  defp normalize_string(nil), do: nil

  defp normalize_string(v) do
    v
    |> to_string()
    |> String.trim()
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(v) do
    v
    |> normalize_string()
    |> case do
      nil -> nil
      "" -> ""
      s -> String.downcase(s)
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp validate_slug_format(changeset) do
    slug = Ash.Changeset.get_attribute(changeset, :slug)

    if is_binary(slug) and slug != "" and Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :slug,
        message: "must be lowercase and contain only letters, numbers, and hyphens"
      )
    end
  end
end
