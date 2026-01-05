defmodule FleetPrompt.Accounts.User do
  use Ash.Resource,
    domain: FleetPrompt.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table("users")
    repo(FleetPrompt.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      allow_nil?(false)
      public?(true)
    end

    attribute :hashed_password, :string do
      sensitive?(true)
      public?(false)
    end

    attribute :name, :string do
      public?(true)
    end

    attribute :role, :atom do
      constraints(one_of: [:user, :admin, :developer])
      default(:user)
      public?(true)
    end

    attribute :confirmed_at, :utc_datetime_usec do
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_email, [:email])
  end

  relationships do
    belongs_to :organization, FleetPrompt.Accounts.Organization do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:email, :name, :organization_id, :role])
      argument(:password, :string, allow_nil?: false, sensitive?: true)

      change(fn changeset, _context ->
        password = Ash.Changeset.get_argument(changeset, :password)

        if is_binary(password) and byte_size(password) > 0 do
          hashed = Bcrypt.hash_pwd_salt(password)
          Ash.Changeset.force_change_attribute(changeset, :hashed_password, hashed)
        else
          changeset
        end
      end)
    end

    update :update do
      accept([:email, :name, :role])
    end

    update :confirm do
      require_atomic?(false)

      change(fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :confirmed_at, DateTime.utc_now())
      end)
    end
  end

  admin do
    table_columns([:email, :name, :role, :confirmed_at, :organization_id])
  end
end
