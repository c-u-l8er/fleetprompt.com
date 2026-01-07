defmodule FleetPrompt.Packages.Installation do
  @moduledoc """
  Tenant-scoped record of a package installation.

  This resource lives in the tenant schema (e.g. `org_demo`) and tracks the
  installation lifecycle for a package that is defined in the global package
  registry (`FleetPrompt.Packages.Package`, stored in the public schema).

  Design notes (Phase 2 / Phase 2B alignment):
  - This is **tenant-scoped** (`multitenancy :context`).
  - It stores a stable package identifier (`package_slug` + `package_version`)
    to avoid cross-schema FK complexity.
  - It supports idempotency via `idempotency_key` (recommended for directive-driven installs).
  - It is intentionally minimal: policies/authorizers are omitted for now.
  """

  use Ash.Resource,
    domain: FleetPrompt.Packages,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  import Ash.Expr
  require Ash.Query

  postgres do
    table("package_installations")
    repo(FleetPrompt.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    # Stable identity of the package being installed (global registry key)
    attribute :package_slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :package_version, :string do
      allow_nil?(false)
      public?(true)
    end

    # Optional convenience snapshot (safe display field; not authoritative)
    attribute :package_name, :string do
      public?(true)
    end

    # Installation lifecycle
    attribute :status, :atom do
      allow_nil?(false)

      constraints(
        one_of: [
          :requested,
          :installing,
          :installed,
          :failed,
          :disabled
        ]
      )

      default(:requested)
      public?(true)
    end

    attribute :enabled, :boolean do
      allow_nil?(false)
      default(true)
      public?(true)
    end

    # Who initiated the installation (public-schema user UUID), if known.
    attribute :installed_by_user_id, :uuid do
      public?(true)
    end

    attribute :installed_at, :utc_datetime_usec do
      public?(true)
    end

    # Arbitrary, package-defined config.
    # IMPORTANT: do not store secrets here without encryption (out of scope for this slice).
    attribute :config, :map do
      default(%{})
      public?(true)
    end

    # Idempotency key for safe retries (recommended for directive-driven installs)
    attribute :idempotency_key, :string do
      public?(true)
    end

    # Error reporting (operationally useful)
    attribute :last_error, :string do
      public?(true)
    end

    attribute :last_error_at, :utc_datetime_usec do
      public?(true)
    end

    timestamps()
  end

  identities do
    # A tenant should have at most one installation record per package slug.
    identity(:unique_package_slug, [:package_slug])

    # Recommended for directive-backed install requests.
    #
    # IMPORTANT: Avoid identity conflicts on `nil` idempotency keys by only enforcing
    # uniqueness when the key is present.
    identity :unique_idempotency_key, [:idempotency_key] do
      where(expr(not is_nil(idempotency_key)))
    end
  end

  actions do
    defaults([:read, :destroy])

    read :by_slug do
      argument(:package_slug, :string, allow_nil?: false)
      get?(true)

      filter(expr(package_slug == ^arg(:package_slug)))
    end

    read :active do
      prepare(fn query, _ctx ->
        query
        |> Ash.Query.filter(
          expr(enabled == true and status in [:requested, :installing, :installed])
        )
      end)
    end

    create :request_install do
      accept([
        :package_slug,
        :package_version,
        :package_name,
        :installed_by_user_id,
        :config,
        :idempotency_key
      ])

      change(set_attribute(:status, :requested))
      change(set_attribute(:enabled, true))
    end

    update :mark_installing do
      require_atomic?(false)

      accept([])
      change(set_attribute(:status, :installing))
      change(set_attribute(:last_error, nil))
      change(set_attribute(:last_error_at, nil))
    end

    update :mark_installed do
      require_atomic?(false)

      accept([])
      change(set_attribute(:status, :installed))

      # IMPORTANT: compute at runtime (module attributes are compiled).
      change(fn changeset, _ctx ->
        Ash.Changeset.force_change_attribute(changeset, :installed_at, DateTime.utc_now())
      end)

      change(set_attribute(:last_error, nil))
      change(set_attribute(:last_error_at, nil))
    end

    update :mark_failed do
      require_atomic?(false)

      argument(:error, :string, allow_nil?: false)
      accept([])

      change(fn changeset, ctx ->
        error =
          case ctx do
            %{arguments: %{error: e}} -> e
            _ -> "Installation failed"
          end

        changeset
        |> Ash.Changeset.force_change_attribute(:status, :failed)
        |> Ash.Changeset.force_change_attribute(:last_error, error)
        |> Ash.Changeset.force_change_attribute(:last_error_at, DateTime.utc_now())
      end)
    end

    update :disable do
      require_atomic?(false)

      accept([])
      change(set_attribute(:enabled, false))
      change(set_attribute(:status, :disabled))
    end

    update :enable do
      require_atomic?(false)

      accept([])
      change(set_attribute(:enabled, true))

      # If previously disabled, put it back into a safe steady state.
      # (If it was installed before disable, keep it installed; otherwise requested.)
      change(fn changeset, _ctx ->
        current = changeset.data.status

        next =
          case current do
            :disabled -> if(changeset.data.installed_at, do: :installed, else: :requested)
            other -> other
          end

        Ash.Changeset.force_change_attribute(changeset, :status, next)
      end)
    end
  end

  calculations do
    calculate(:is_installed, :boolean, expr(status == :installed and enabled == true))
  end

  admin do
    table_columns([
      :package_slug,
      :package_version,
      :status,
      :enabled,
      :installed_at,
      :inserted_at
    ])
  end
end
