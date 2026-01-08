defmodule FleetPrompt.Agents.Execution do
  @moduledoc """
  Tenant-scoped Execution resource for agent runs.

  This represents a single "run" of an agent, including:
  - requested input (and optional structured request payload)
  - lifecycle state (queued/running/succeeded/failed/canceled)
  - model + generation params used
  - token usage + (optional) cost accounting

  Notes:
  - This resource is tenant-scoped (schema-per-tenant) via `multitenancy :context`.
  - Cost calculation is best-effort and depends on optional pricing config.
  """

  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [
      AshStateMachine,
      AshAdmin.Resource
    ]

  postgres do
    table("executions")
    repo(FleetPrompt.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  # -----------------------
  # Attributes
  # -----------------------

  attributes do
    uuid_primary_key(:id)

    # Model / provider settings used for the run.
    attribute :model, :string do
      allow_nil?(false)
      default("openrouter/anthropic/claude-3.5-sonnet")
      public?(true)
    end

    attribute :temperature, :float do
      allow_nil?(false)
      default(0.7)
      constraints(min: 0.0, max: 2.0)
      public?(true)
    end

    attribute :max_tokens, :integer do
      allow_nil?(false)
      default(1024)
      constraints(min: 1, max: 200_000)
      public?(true)
    end

    # Lifecycle state for the run.
    attribute :state, :atom do
      allow_nil?(false)
      constraints(one_of: [:queued, :running, :succeeded, :failed, :canceled])
      default(:queued)
      public?(true)
    end

    # The "user input" for the run (simple MVP shape).
    attribute :input, :string do
      allow_nil?(false)
      public?(true)
    end

    # Optional structured request payload (messages, tools, etc.).
    # Keep JSON-safe, do not store secrets here.
    attribute :request, :map do
      default(%{})
      public?(true)
    end

    # Output content, if succeeded. If failed (or still queued/running), this may be empty/nil.
    #
    # NOTE:
    # - We do *not* want to require clients to provide `output` when requesting an execution.
    # - Keep this attribute nullable at the Ash layer to avoid request-time validation failures.
    attribute :output, :string do
      default("")
      public?(true)
    end

    # Failure info (sanitized); do not store secrets.
    attribute :error, :string do
      public?(true)
    end

    # Token accounting (optional; filled by executor).
    attribute :prompt_tokens, :integer do
      constraints(min: 0)
      default(0)
      public?(true)
    end

    attribute :completion_tokens, :integer do
      constraints(min: 0)
      default(0)
      public?(true)
    end

    attribute :total_tokens, :integer do
      constraints(min: 0)
      default(0)
      public?(true)
    end

    # Cost accounting (optional).
    # Prefer storing in cents to avoid float drift.
    attribute :cost_cents, :integer do
      constraints(min: 0)
      public?(true)
    end

    # Timing (optional but helpful for ops).
    attribute :started_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :finished_at, :utc_datetime_usec do
      public?(true)
    end

    # Free-form metadata (correlation ids, safe tags, etc.).
    attribute :metadata, :map do
      default(%{})
      public?(true)
    end

    timestamps()
  end

  # -----------------------
  # Relationships
  # -----------------------

  relationships do
    belongs_to :agent, FleetPrompt.Agents.Agent do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end
  end

  # -----------------------
  # State machine
  # -----------------------

  state_machine do
    initial_states([:queued])
    default_initial_state(:queued)

    transitions do
      transition(:mark_running, from: :queued, to: :running)
      transition(:mark_succeeded, from: :running, to: :succeeded)
      transition(:mark_failed, from: :running, to: :failed)
      transition(:mark_canceled, from: [:queued, :running], to: :canceled)
    end
  end

  # -----------------------
  # Actions
  # -----------------------

  actions do
    defaults([:read, :destroy])

    # Create a new execution request (typically enqueued to an Oban job).
    create :request do
      accept([
        :agent_id,
        :input,
        :request,
        :metadata,
        :model,
        :max_tokens,
        :temperature
      ])

      # Intentionally do not set `output` at request time.
      # It will be populated by the executor when the run succeeds.
    end

    # Transition to running; set started_at if not already set.
    update :mark_running do
      accept([:metadata])
      require_atomic?(false)

      change(transition_state(:running))

      change(fn changeset, _ctx ->
        case Ash.Changeset.get_attribute(changeset, :started_at) do
          nil -> Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
          _ -> changeset
        end
      end)
    end

    # Mark succeeded. Token usage/cost may be provided by the executor job.
    update :mark_succeeded do
      accept([:output, :prompt_tokens, :completion_tokens, :total_tokens, :cost_cents, :metadata])
      require_atomic?(false)

      change(transition_state(:succeeded))
      change(FleetPrompt.Agents.Execution.Changes.FinalizeAccounting)
      change(FleetPrompt.Agents.Execution.Changes.SetFinishedAt)
    end

    # Mark failed with sanitized error message.
    update :mark_failed do
      accept([:error, :prompt_tokens, :completion_tokens, :total_tokens, :cost_cents, :metadata])
      require_atomic?(false)

      change(transition_state(:failed))
      change(FleetPrompt.Agents.Execution.Changes.FinalizeAccounting)
      change(FleetPrompt.Agents.Execution.Changes.SetFinishedAt)
    end

    update :mark_canceled do
      accept([:metadata])
      require_atomic?(false)

      change(transition_state(:canceled))
      change(FleetPrompt.Agents.Execution.Changes.SetFinishedAt)
    end

    # Convenience read: list executions for an agent.
    read :for_agent do
      argument :agent_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(agent_id == ^arg(:agent_id)))
    end
  end

  # -----------------------
  # Admin
  # -----------------------

  admin do
    table_columns([:agent_id, :state, :model, :total_tokens, :cost_cents, :inserted_at])
  end
end

defmodule FleetPrompt.Agents.Execution.Changes.SetFinishedAt do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    case Ash.Changeset.get_attribute(changeset, :finished_at) do
      nil -> Ash.Changeset.change_attribute(changeset, :finished_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end

defmodule FleetPrompt.Agents.Execution.Changes.FinalizeAccounting do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    prompt_tokens = Ash.Changeset.get_attribute(changeset, :prompt_tokens) || 0
    completion_tokens = Ash.Changeset.get_attribute(changeset, :completion_tokens) || 0

    changeset =
      case Ash.Changeset.get_attribute(changeset, :total_tokens) do
        0 -> Ash.Changeset.change_attribute(changeset, :total_tokens, prompt_tokens + completion_tokens)
        nil -> Ash.Changeset.change_attribute(changeset, :total_tokens, prompt_tokens + completion_tokens)
        _ -> changeset
      end

    # If cost_cents was provided by the executor, keep it.
    # Otherwise, attempt a best-effort pricing lookup from config:
    #   config :fleet_prompt, :llm_pricing, %{
    #     "openrouter/anthropic/claude-3.5-sonnet" => %{
    #       "prompt_cents_per_1k" => 3,
    #       "completion_cents_per_1k" => 15
    #     }
    #   }
    case Ash.Changeset.get_attribute(changeset, :cost_cents) do
      nil ->
        model = Ash.Changeset.get_attribute(changeset, :model)

        case calculate_cost_cents(model, prompt_tokens, completion_tokens) do
          nil -> changeset
          cents -> Ash.Changeset.change_attribute(changeset, :cost_cents, cents)
        end

      _ ->
        changeset
    end
  end

  defp calculate_cost_cents(model, prompt_tokens, completion_tokens)
       when is_binary(model) and is_integer(prompt_tokens) and is_integer(completion_tokens) do
    pricing = Application.get_env(:fleet_prompt, :llm_pricing, %{})

    with %{} = model_pricing <- Map.get(pricing, model),
         prompt_rate when is_integer(prompt_rate) <- Map.get(model_pricing, "prompt_cents_per_1k"),
         completion_rate when is_integer(completion_rate) <- Map.get(model_pricing, "completion_cents_per_1k") do
      prompt_cents = div(prompt_tokens * prompt_rate, 1000)
      completion_cents = div(completion_tokens * completion_rate, 1000)
      max(prompt_cents + completion_cents, 0)
    else
      _ -> nil
    end
  end
end
