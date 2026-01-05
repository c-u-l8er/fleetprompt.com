defmodule FleetPrompt.Agents.Agent do
  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshStateMachine,
      AshAdmin.Resource
    ]

  postgres do
    table("agents")
    repo(FleetPrompt.Repo)
  end

  # Schema-per-tenant isolation: tenant is provided via Ash context (e.g. `Ash.Changeset.set_tenant/2`)
  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :version, :string do
      default("1.0.0")
      public?(true)
    end

    # State machine field (AshStateMachine uses `:state` by default)
    attribute :state, :atom do
      allow_nil?(false)
      constraints(one_of: [:draft, :deploying, :active, :paused, :error])
      default(:draft)
      public?(true)
    end

    # Runtime configuration (stored as JSON/map)
    attribute :config, :map do
      default(%{
        "model" => "claude-sonnet-4",
        "max_tokens" => 4096,
        "temperature" => 0.7
      })

      public?(true)
    end

    attribute :system_prompt, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :max_concurrent_requests, :integer do
      default(5)
      public?(true)
    end

    attribute :timeout_seconds, :integer do
      default(30)
      public?(true)
    end

    # Basic metrics
    attribute :total_executions, :integer do
      default(0)
      public?(true)
    end

    attribute :total_tokens_used, :integer do
      default(0)
      public?(true)
    end

    attribute :avg_latency_ms, :integer do
      public?(true)
    end

    timestamps()
  end

  # State machine configuration.
  # Note: action implementations below invoke `transition_state/1` by transition name.
  state_machine do
    initial_states([:draft])
    default_initial_state(:draft)

    transitions do
      transition(:deploy, from: :draft, to: :deploying)
      transition(:activate, from: :deploying, to: :active)
      transition(:pause, from: :active, to: :paused)
      transition(:resume, from: :paused, to: :active)
      transition(:error, from: [:deploying, :active], to: :error)
      transition(:redeploy, from: :error, to: :deploying)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :description, :system_prompt, :config])
    end

    update :update do
      accept([
        :name,
        :description,
        :system_prompt,
        :config,
        :max_concurrent_requests,
        :timeout_seconds
      ])
    end

    # State transitions as explicit actions
    update :deploy do
      change(transition_state(:deploying))
    end

    update :activate do
      change(transition_state(:active))
    end

    update :pause do
      change(transition_state(:paused))
    end

    update :resume do
      change(transition_state(:active))
    end

    update :error do
      change(transition_state(:error))
    end

    update :redeploy do
      change(transition_state(:deploying))
    end
  end

  # NOTE: Policies/authorizers are intentionally omitted for now to avoid requiring a SAT solver.

  admin do
    table_columns([:name, :state, :version, :total_executions])
  end
end
