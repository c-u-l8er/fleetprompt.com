# FleetPrompt - Phase 4: Agent Execution & Workflows

## Overview
This phase should be treated as the **platform core**: a **signal-driven execution and workflow system** with first-class **observability**. Instead of “run an agent” as an isolated job, everything becomes:

- **Signals** (immutable events) flowing through
- **Runs** (stateful executions) that consume/emit signals
- **Workflows** as orchestrated signal chains
- **Telemetry** as a mandatory output of every run step

This aligns with the Jido-style architecture you’ve researched: predictable event flow, composability, and debuggability (replay/time-travel) rather than ad-hoc background jobs.

### Architecture (Phase 4, realigned)

```
User/API/Integration
      ↓ emits
   Signal (immutable, persisted, replayable)
      ↓ routed by
   Signal Bus (middleware, auth, rate-limit, fanout)
      ↓ starts/advances
   Run (Execution) + Step Logs (append-only)
      ↓ emits
   More Signals (next steps, side-effects, webhooks)
      ↓ observed by
   Telemetry + Tracing (correlation IDs everywhere)
```

## Prerequisites
- ✅ Phase 0-1 completed (Inertia + Svelte; core multi-tenancy + auth/org context)
- ⚠️ Phase 2-3 can be incremental, but Phase 4 should NOT assume chat is the primary driver
  - Chat is just one signal source; integrations + API are equal first-class inputs.

## Phase 4 Goals (Realigned)

1. Define a **Signal** envelope and persistence/replay strategy (debugging + supportability).
2. Make **Execution = Run** the canonical state machine that consumes signals and produces signals.
3. Implement **step-level logging** (append-only) + structured errors + compensation hooks (saga-style).
4. Add **correlation + causation identifiers** to everything (traceability across integrations).
5. Add **telemetry events** for run lifecycle, step lifecycle, tool calls, costs, and failures.
6. Provide a minimal **Run inspection UI** (even if basic) to make debugging possible in prod.
7. Keep the LLM client and tool system, but treat them as **effects invoked by steps**, not the architecture.

## Backend Implementation

### Step 1: Create Run (Execution) Resource — Signal-driven + Traceable

Create `lib/fleet_prompt/agents/execution.ex` as the **Run** record (still named “Execution” if you prefer), but it must be able to answer:

- *What signal started this?* (causation)
- *What other work is this related to?* (correlation)
- *How do I trace it across systems?* (trace/span)
- *Can I safely retry?* (idempotency + attempts)
- *What happened step-by-step?* (logs/events)

Create `lib/fleet_prompt/agents/execution.ex`:

```elixir
defmodule FleetPrompt.Agents.Execution do
  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "agent_executions"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id

    # --- Traceability / event lineage (non-negotiable for integrations) ---
    # correlation_id: groups related work across systems (email thread, webhook chain, etc.)
    # causation_id: points to the specific triggering event/signal/run step
    attribute :correlation_id, :string do
      public? true
    end

    attribute :causation_id, :string do
      public? true
    end

    # Optional W3C-ish tracing fields (keep as strings for portability)
    attribute :trace_id, :string do
      public? true
    end

    attribute :span_id, :string do
      public? true
    end

    attribute :parent_span_id, :string do
      public? true
    end

    # The triggering signal (if/when you add a signals table, this becomes a FK/uuid)
    attribute :signal_id, :uuid do
      public? true
    end

    # Idempotency + retries (required for webhooks + background jobs)
    attribute :idempotency_key, :string do
      public? true
    end

    attribute :attempt, :integer do
      default 0
      public? true
    end

    # --- Run lifecycle ---
    attribute :status, :atom do
      constraints one_of: [:queued, :running, :completed, :failed, :cancelled]
      default :queued
      public? true
    end

    # Keep inputs/outputs, but treat them as structured “step context”
    attribute :input, :map do
      allow_nil? false
      public? true
    end

    attribute :output, :map do
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    attribute :error_kind, :string do
      public? true
    end

    attribute :error_details, :map do
      default %{}
      public? true
    end

    # --- Usage + cost + effects (observability-friendly) ---
    attribute :model, :string do
      public? true
    end

    attribute :tool_calls, {:array, :map} do
      default []
      public? true
    end

    attribute :input_tokens, :integer do
      default 0
      public? true
    end

    attribute :output_tokens, :integer do
      default 0
      public? true
    end

    attribute :total_tokens, :integer do
      default 0
      public? true
    end

    attribute :latency_ms, :integer do
      public? true
    end

    attribute :cost_usd, :decimal do
      public? true
    end

    # Execution context should carry tenant/org + step routing hints (but never secrets)
    attribute :context, :map do
      default %{}
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end
  
  state_machine do
    initial_states [:queued]
    default_initial_state :queued
    
    transitions do
      transition :start, from: :queued, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: :running, to: :failed
      transition :cancel, from: [:queued, :running], to: :cancelled
    end
  end
  
  actions do
    defaults [:read]
    
    create :create do
      accept [:input, :context]
      argument :agent_id, :uuid, allow_nil? false
      
      change fn changeset, context ->
        agent_id = Ash.Changeset.get_argument(changeset, :agent_id)
        
        # Load agent to get config
        agent = FleetPrompt.Agents.Agent
                |> Ash.get!(agent_id, tenant: context.tenant)
        
        changeset
        |> Ash.Changeset.manage_relationship(:agent, agent, type: :append)
        |> Ash.Changeset.force_change_attribute(:model, agent.config["model"])
      end
      
      after_action fn _changeset, execution, context ->
        # Queue execution job
        {:ok, _job} = FleetPrompt.Jobs.AgentExecutor.enqueue(%{
          execution_id: execution.id,
          tenant: context.tenant
        })
        
        {:ok, execution}
      end
    end
    
    update :start do
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :running)
        |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())
      end
    end
    
    update :complete do
      argument :output, :map, allow_nil: false
      argument :tokens, :map, allow_nil? false
      argument :latency_ms, :integer, allow_nil? false
      
      change fn changeset, _context ->
        output = Ash.Changeset.get_argument(changeset, :output)
        tokens = Ash.Changeset.get_argument(changeset, :tokens)
        latency = Ash.Changeset.get_argument(changeset, :latency_ms)
        
        total_tokens = tokens.input + tokens.output
        cost = calculate_cost(changeset.data.model, total_tokens)
        
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :completed)
        |> Ash.Changeset.force_change_attribute(:output, output)
        |> Ash.Changeset.force_change_attribute(:input_tokens, tokens.input)
        |> Ash.Changeset.force_change_attribute(:output_tokens, tokens.output)
        |> Ash.Changeset.force_change_attribute(:total_tokens, total_tokens)
        |> Ash.Changeset.force_change_attribute(:latency_ms, latency)
        |> Ash.Changeset.force_change_attribute(:cost_usd, cost)
        |> Ash.Changeset.force_change_attribute(:completed_at, DateTime.utc_now())
      end
    end
    
    update :fail do
      argument :error, :string, allow_nil? false
      
      change fn changeset, _context ->
        error = Ash.Changeset.get_argument(changeset, :error)
        
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :failed)
        |> Ash.Changeset.force_change_attribute(:error_message, error)
        |> Ash.Changeset.force_change_attribute(:completed_at, DateTime.utc_now())
      end
    end
  end
  
  relationships do
    belongs_to :agent, FleetPrompt.Agents.Agent
    has_many :logs, FleetPrompt.Agents.ExecutionLog
  end
  
  calculations do
    calculate :duration_ms, :integer do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          if record.started_at && record.completed_at do
            DateTime.diff(record.completed_at, record.started_at, :millisecond)
          else
            nil
          end
        end)
      end
    end
  end
  
  defp calculate_cost(model, total_tokens) do
    # Pricing per 1M tokens (example rates)
    rate = case model do
      "claude-sonnet-4" -> Decimal.new("3.00")  # $3 per 1M tokens
      "claude-opus-4" -> Decimal.new("15.00")   # $15 per 1M tokens
      "gpt-4" -> Decimal.new("30.00")           # $30 per 1M tokens
      _ -> Decimal.new("3.00")
    end
    
    Decimal.mult(rate, Decimal.div(Decimal.new(total_tokens), Decimal.new(1_000_000)))
  end
end
```

### Step 2: Create Execution Log Resource

Create `lib/fleet_prompt/agents/execution_log.ex`:

```elixir
defmodule FleetPrompt.Agents.ExecutionLog do
  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "agent_execution_logs"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :level, :atom do
      constraints one_of: [:debug, :info, :warning, :error]
      default :info
      public? true
    end
    
    attribute :message, :string do
      allow_nil? false
      public? true
    end
    
    attribute :data, :map do
      default %{}
      public? true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create]
  end
  
  relationships do
    belongs_to :execution, FleetPrompt.Agents.Execution
  end
end
```

### Step 3: Create LLM Client

Create `lib/fleet_prompt/llm/client.ex`:

```elixir
defmodule FleetPrompt.LLM.Client do
  @moduledoc """
  Client for LLM APIs (Claude, GPT, etc.)
  """
  
  require Logger
  
  def chat_completion(messages, opts \\ []) do
    model = Keyword.get(opts, :model, "claude-sonnet-4")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    temperature = Keyword.get(opts, :temperature, 0.7)
    tools = Keyword.get(opts, :tools, [])
    
    start_time = System.monotonic_time(:millisecond)
    
    request_body = %{
      model: model,
      messages: messages,
      max_tokens: max_tokens,
      temperature: temperature
    }
    
    request_body = if length(tools) > 0 do
      Map.put(request_body, :tools, tools)
    else
      request_body
    end
    
    result = case get_provider(model) do
      :anthropic -> call_anthropic(request_body)
      :openai -> call_openai(request_body)
    end
    
    end_time = System.monotonic_time(:millisecond)
    latency = end_time - start_time
    
    case result do
      {:ok, response} ->
        {:ok, %{
          content: response.content,
          usage: response.usage,
          latency_ms: latency
        }}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp call_anthropic(request) do
    api_key = Application.get_env(:fleet_prompt, :anthropic_api_key)
    
    case Req.post("https://api.anthropic.com/v1/messages",
      json: request,
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ]
    ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{
          content: extract_content(body),
          usage: %{
            input: body["usage"]["input_tokens"],
            output: body["usage"]["output_tokens"]
          }
        }}
      {:ok, %{status: status, body: body}} ->
        Logger.error("Anthropic API error: #{status} - #{inspect(body)}")
        {:error, "API error: #{status}"}
      {:error, reason} ->
        Logger.error("Anthropic request failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
  
  defp call_openai(request) do
    api_key = Application.get_env(:fleet_prompt, :openai_api_key)
    
    case Req.post("https://api.openai.com/v1/chat/completions",
      json: request,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]
    ) do
      {:ok, %{status: 200, body: body}} ->
        choice = List.first(body["choices"])
        {:ok, %{
          content: choice["message"]["content"],
          usage: %{
            input: body["usage"]["prompt_tokens"],
            output: body["usage"]["completion_tokens"]
          }
        }}
      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
        {:error, "API error: #{status}"}
      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
  
  defp extract_content(response) do
    response["content"]
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(&(&1["text"]))
    |> Enum.join("\n")
  end
  
  defp get_provider("claude" <> _), do: :anthropic
  defp get_provider("gpt" <> _), do: :openai
  defp get_provider(_), do: :anthropic
end
```

### Step 4: Create Agent Executor Job

Create `lib/fleet_prompt/jobs/agent_executor.ex`:

```elixir
defmodule FleetPrompt.Jobs.AgentExecutor do
  use Oban.Worker, queue: :agents, max_attempts: 3
  
  alias FleetPrompt.Agents.{Agent, Execution, ExecutionLog}
  alias FleetPrompt.LLM.Client
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id, "tenant" => tenant}}) do
    execution = load_execution(execution_id, tenant)
    agent = load_agent(execution.agent_id, tenant)
    
    # Mark as running
    {:ok, execution} = execution
      |> Ash.Changeset.for_update(:start)
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.update()
    
    log(execution, :info, "Starting execution", %{agent: agent.name}, tenant)
    
    # Build messages
    messages = [
      %{
        role: "user",
        content: build_prompt(agent, execution)
      }
    ]
    
    # Add system prompt if present
    messages = if agent.system_prompt do
      [%{role: "system", content: agent.system_prompt} | messages]
    else
      messages
    end
    
    # Execute
    case Client.chat_completion(messages,
      model: agent.config["model"],
      max_tokens: agent.config["max_tokens"] || 4096,
      temperature: agent.config["temperature"] || 0.7
    ) do
      {:ok, result} ->
        log(execution, :info, "Execution completed", %{tokens: result.usage.input + result.usage.output}, tenant)
        
        # Mark as completed
        execution
        |> Ash.Changeset.for_update(:complete, %{
          output: %{response: result.content},
          tokens: result.usage,
          latency_ms: result.latency_ms
        })
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.update!()
        
        # Update agent metrics
        update_agent_metrics(agent, result, tenant)
        
        :ok
        
      {:error, reason} ->
        log(execution, :error, "Execution failed", %{error: reason}, tenant)
        
        execution
        |> Ash.Changeset.for_update(:fail, %{error: inspect(reason)})
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.update!()
        
        {:error, reason}
    end
  end
  
  defp load_execution(id, tenant) do
    Execution
    |> Ash.get!(id, tenant: tenant)
  end
  
  defp load_agent(id, tenant) do
    Agent
    |> Ash.get!(id, tenant: tenant)
  end
  
  defp build_prompt(agent, execution) do
    """
    Agent: #{agent.name}
    Description: #{agent.description}
    
    Input:
    #{Jason.encode!(execution.input, pretty: true)}
    
    Please process this input according to the agent's purpose.
    """
  end
  
  defp log(execution, level, message, data, tenant) do
    ExecutionLog
    |> Ash.Changeset.for_create(:create, %{
      execution_id: execution.id,
      level: level,
      message: message,
      data: data
    })
    |> Ash.Changeset.set_tenant(tenant)
    |> Ash.create()
  end
  
  defp update_agent_metrics(agent, result, tenant) do
    current_executions = agent.total_executions
    current_tokens = agent.total_tokens_used
    current_latency = agent.avg_latency_ms || 0
    
    new_executions = current_executions + 1
    new_tokens = current_tokens + result.usage.input + result.usage.output
    new_latency = div(current_latency * current_executions + result.latency_ms, new_executions)
    
    agent
    |> Ash.Changeset.for_update(:update, %{
      total_executions: new_executions,
      total_tokens_used: new_tokens,
      avg_latency_ms: new_latency
    })
    |> Ash.Changeset.set_tenant(tenant)
    |> Ash.update()
  end
end
```

### Step 5: Create Workflow Resource

Create `lib/fleet_prompt/workflows/workflow.ex`:

```elixir
defmodule FleetPrompt.Workflows.Workflow do
  use Ash.Resource,
    domain: FleetPrompt.Workflows,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "workflows"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string do
      allow_nil? false
      public? true
    end
    
    attribute :description, :string do
      public? true
    end
    
    attribute :status, :atom do
      constraints one_of: [:draft, :active, :paused, :archived]
      default :draft
      public? true
    end
    
    # DAG definition
    attribute :definition, :map do
      allow_nil? false
      public? true
    end
    
    # Metrics
    attribute :total_runs, :integer do
      default 0
      public? true
    end
    
    attribute :successful_runs, :integer do
      default 0
      public? true
    end
    
    attribute :failed_runs, :integer do
      default 0
      public? true
    end
    
    timestamps()
  end
  
  state_machine do
    initial_states [:draft]
    default_initial_state :draft
    
    transitions do
      transition :activate, from: :draft, to: :active
      transition :pause, from: :active, to: :paused
      transition :resume, from: :paused, to: :active
      transition :archive, from: [:active, :paused], to: :archived
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create do
      accept [:name, :description, :definition]
      
      validate fn changeset, _context ->
        definition = Ash.Changeset.get_attribute(changeset, :definition)
        
        case validate_workflow_definition(definition) do
          :ok -> :ok
          {:error, reason} -> {:error, field: :definition, message: reason}
        end
      end
    end
    
    update :activate, do: change transition_state(:active)
    update :pause, do: change transition_state(:paused)
  end
  
  relationships do
    has_many :runs, FleetPrompt.Workflows.WorkflowRun
  end
  
  defp validate_workflow_definition(definition) do
    cond do
      !is_map(definition) ->
        {:error, "Definition must be a map"}
      !Map.has_key?(definition, "steps") ->
        {:error, "Definition must have 'steps' key"}
      !is_list(definition["steps"]) ->
        {:error, "Steps must be an array"}
      length(definition["steps"]) == 0 ->
        {:error, "Must have at least one step"}
      true ->
        :ok
    end
  end
end
```

### Step 6: Create Workflow Run Resource

Create `lib/fleet_prompt/workflows/workflow_run.ex`:

```elixir
defmodule FleetPrompt.Workflows.WorkflowRun do
  use Ash.Resource,
    domain: FleetPrompt.Workflows,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "workflow_runs"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :status, :atom do
      constraints one_of: [:queued, :running, :completed, :failed, :cancelled]
      default :queued
      public? true
    end
    
    attribute :input, :map do
      allow_nil? false
      public? true
    end
    
    attribute :output, :map do
      public? true
    end
    
    attribute :step_results, :map do
      default %{}
      public? true
    end
    
    attribute :current_step, :integer do
      default 0
      public? true
    end
    
    attribute :error_message, :string do
      public? true
    end
    
    attribute :started_at, :utc_datetime_usec do
      public? true
    end
    
    attribute :completed_at, :utc_datetime_usec do
      public? true
    end
    
    timestamps()
  end
  
  state_machine do
    initial_states [:queued]
    default_initial_state :queued
    
    transitions do
      transition :start, from: :queued, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: :running, to: :failed
      transition :cancel, from: [:queued, :running], to: :cancelled
    end
  end
  
  actions do
    defaults [:read]
    
    create :create do
      accept [:input]
      argument :workflow_id, :uuid, allow_nil? false
      
      change fn changeset, context ->
        workflow_id = Ash.Changeset.get_argument(changeset, :workflow_id)
        
        changeset
        |> Ash.Changeset.manage_relationship(:workflow, %{id: workflow_id}, type: :append)
      end
      
      after_action fn _changeset, run, context ->
        # Queue workflow execution
        {:ok, _job} = FleetPrompt.Jobs.WorkflowExecutor.enqueue(%{
          run_id: run.id,
          tenant: context.tenant
        })
        
        {:ok, run}
      end
    end
  end
  
  relationships do
    belongs_to :workflow, FleetPrompt.Workflows.Workflow
  end
end
```

### Step 7: Create Workflow Executor

Create `lib/fleet_prompt/jobs/workflow_executor.ex`:

```elixir
defmodule FleetPrompt.Jobs.WorkflowExecutor do
  use Oban.Worker, queue: :workflows, max_attempts: 3
  
  alias FleetPrompt.Workflows.{Workflow, WorkflowRun}
  alias FleetPrompt.Agents.{Agent, Execution}
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id, "tenant" => tenant}}) do
    run = load_run(run_id, tenant)
    workflow = load_workflow(run.workflow_id, tenant)
    
    # Mark as running
    {:ok, run} = run
      |> Ash.Changeset.for_update(:start)
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.update()
    
    # Execute steps
    result = execute_steps(workflow, run, tenant)
    
    case result do
      {:ok, final_output} ->
        run
        |> Ash.Changeset.for_update(:complete, %{output: final_output})
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.update!()
        
        :ok
        
      {:error, reason} ->
        run
        |> Ash.Changeset.for_update(:fail, %{error: inspect(reason)})
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.update!()
        
        {:error, reason}
    end
  end
  
  defp execute_steps(workflow, run, tenant) do
    steps = workflow.definition["steps"]
    
    Enum.reduce_while(steps, {:ok, run.input}, fn step, {:ok, context} ->
      case execute_step(step, context, tenant) do
        {:ok, result} ->
          # Update run with step result
          step_results = Map.put(run.step_results, step["id"], result)
          {:ok, run} = run
            |> Ash.Changeset.for_update(:update, %{step_results: step_results})
            |> Ash.Changeset.set_tenant(tenant)
            |> Ash.update()
          
          {:cont, {:ok, Map.merge(context, result)}}
          
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
  
  defp execute_step(step, context, tenant) do
    case step["type"] do
      "agent" ->
        execute_agent_step(step, context, tenant)
      "condition" ->
        execute_condition_step(step, context)
      "parallel" ->
        execute_parallel_step(step, context, tenant)
      _ ->
        {:error, "Unknown step type: #{step["type"]}"}
    end
  end
  
  defp execute_agent_step(step, context, tenant) do
    agent = Agent
            |> Ash.get!(step["agent_id"], tenant: tenant)
    
    {:ok, execution} = Execution
      |> Ash.Changeset.for_create(:create, %{
        agent_id: agent.id,
        input: context,
        context: %{workflow_step: step["id"]}
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()
    
    # Wait for execution to complete (poll)
    wait_for_execution(execution, tenant)
  end
  
  defp wait_for_execution(execution, tenant, attempts \\ 0) do
    if attempts > 60 do
      {:error, "Execution timeout"}
    else
      execution = Execution |> Ash.get!(execution.id, tenant: tenant)
      
      case execution.status do
        :completed -> {:ok, execution.output}
        :failed -> {:error, execution.error_message}
        _ ->
          Process.sleep(1000)
          wait_for_execution(execution, tenant, attempts + 1)
      end
    end
  end
  
  defp execute_condition_step(step, context) do
    # Evaluate condition
    condition = step["condition"]
    result = evaluate_condition(condition, context)
    
    {:ok, %{condition_result: result}}
  end
  
  defp execute_parallel_step(step, context, tenant) do
    # Execute sub-steps in parallel
    tasks = Enum.map(step["steps"], fn sub_step ->
      Task.async(fn -> execute_step(sub_step, context, tenant) end)
    end)
    
    results = Task.await_many(tasks, :infinity)
    
    if Enum.all?(results, fn {status, _} -> status == :ok end) do
      merged = results
               |> Enum.map(fn {:ok, result} -> result end)
               |> Enum.reduce(%{}, &Map.merge/2)
      
      {:ok, merged}
    else
      {:error, "One or more parallel steps failed"}
    end
  end
  
  defp evaluate_condition(_condition, _context) do
    # Simple condition evaluation
    # In production, use a proper expression evaluator
    true
  end
  
  defp load_run(id, tenant) do
    WorkflowRun |> Ash.get!(id, tenant: tenant)
  end
  
  defp load_workflow(id, tenant) do
    Workflow |> Ash.get!(id, tenant: tenant)
  end
end
```

### Step 8: Update Domains

Update `lib/fleet_prompt/workflows.ex`:

```elixir
defmodule FleetPrompt.Workflows do
  use Ash.Domain

  resources do
    resource FleetPrompt.Workflows.Workflow
    resource FleetPrompt.Workflows.WorkflowRun
  end
end
```

### Step 9: Generate Migrations

```bash
mix ash_postgres.generate_migrations --name add_executions_and_workflows
mix ecto.migrate
```

### Step 10: Add API Keys to Config

Update `config/config.exs`:

```elixir
config :fleet_prompt,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

## Frontend Implementation

### Step 11: Create Execution Controller

Create `lib/fleet_prompt_web/controllers/execution_controller.ex`:

```elixir
defmodule FleetPromptWeb.ExecutionController do
  use FleetPromptWeb, :controller
  
  def index(conn, _params) do
    current_org = conn.assigns[:current_org]
    
    executions = FleetPrompt.Agents.Execution
                 |> Ash.Query.sort(inserted_at: :desc)
                 |> Ash.Query.limit(50)
                 |> Ash.Query.set_tenant(current_org)
                 |> Ash.read!()
    
    render_inertia(conn, "Executions/Index",
      props: %{
        executions: serialize_executions(executions)
      }
    )
  end
  
  def show(conn, %{"id" => id}) do
    current_org = conn.assigns[:current_org]
    
    execution = FleetPrompt.Agents.Execution
                |> Ash.get!(id, tenant: current_org)
    
    logs = FleetPrompt.Agents.ExecutionLog
           |> Ash.Query.filter(execution_id == ^id)
           |> Ash.Query.sort(inserted_at: :asc)
           |> Ash.Query.set_tenant(current_org)
           |> Ash.read!()
    
    render_inertia(conn, "Executions/Show",
      props: %{
        execution: serialize_execution_detail(execution),
        logs: serialize_logs(logs)
      }
    )
  end
  
  defp serialize_executions(executions) do
    Enum.map(executions, fn exec ->
      %{
        id: exec.id,
        status: exec.status,
        latency_ms: exec.latency_ms,
        total_tokens: exec.total_tokens,
        cost_usd: exec.cost_usd,
        inserted_at: exec.inserted_at
      }
    end)
  end
  
  defp serialize_execution_detail(exec) do
    Map.merge(serialize_executions([exec]) |> List.first(), %{
      input: exec.input,
      output: exec.output,
      error_message: exec.error_message,
      model: exec.model,
      tool_calls: exec.tool_calls,
      started_at: exec.started_at,
      completed_at: exec.completed_at
    })
  end
  
  defp serialize_logs(logs) do
    Enum.map(logs, fn log ->
      %{
        id: log.id,
        level: log.level,
        message: log.message,
        data: log.data,
        inserted_at: log.inserted_at
      }
    end)
  end
end
```

### Step 12: Create Execution Index Page

Create `assets/src/pages/Executions/Index.svelte`:

```svelte
<script lang="ts">
  import { router } from '@inertiajs/svelte';
  import Card from '$lib/components/ui/card/Card.svelte';
  import CardHeader from '$lib/components/ui/card/CardHeader.svelte';
  import CardTitle from '$lib/components/ui/card/CardTitle.svelte';
  import CardContent from '$lib/components/ui/card/CardContent.svelte';
  import Button from '$lib/components/ui/button/Button.svelte';
  import { CheckCircle, XCircle, Clock, Loader } from 'lucide-svelte';
  
  interface Execution {
    id: string;
    status: string;
    latency_ms: number;
    total_tokens: number;
    cost_usd: string;
    inserted_at: string;
  }
  
  interface Props {
    executions: Execution[];
  }
  
  let { executions }: Props = $props();
  
  function getStatusIcon(status: string) {
    switch (status) {
      case 'completed': return CheckCircle;
      case 'failed': return XCircle;
      case 'running': return Loader;
      default: return Clock;
    }
  }
  
  function getStatusColor(status: string) {
    switch (status) {
      case 'completed': return 'text-green-600';
      case 'failed': return 'text-red-600';
      case 'running': return 'text-blue-600';
      default: return 'text-gray-600';
    }
  }
  
  function formatDuration(ms: number) {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  }
</script>

<div class="min-h-screen bg-background p-8">
  <div class="max-w-7xl mx-auto">
    <div class="mb-8">
      <h1 class="text-3xl font-bold mb-2">Agent Executions</h1>
      <p class="text-muted-foreground">Monitor and analyze agent execution history</p>
    </div>
    
    <div class="grid gap-4">
      {#each executions as execution (execution.id)}
        <Card>
          <CardContent class="p-6">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-4">
                <svelte:component 
                  this={getStatusIcon(execution.status)} 
                  class="w-5 h-5 {getStatusColor(execution.status)}"
                />
                <div>
                  <div class="font-medium capitalize">{execution.status}</div>
                  <div class="text-sm text-muted-foreground">
                    {new Date(execution.inserted_at).toLocaleString()}
                  </div>
                </div>
              </div>
              
              <div class="flex items-center gap-6 text-sm">
                <div>
                  <span class="text-muted-foreground">Duration:</span>
                  <span class="ml-2 font-medium">{formatDuration(execution.latency_ms)}</span>
                </div>
                <div>
                  <span class="text-muted-foreground">Tokens:</span>
                  <span class="ml-2 font-medium">{execution.total_tokens.toLocaleString()}</span>
                </div>
                <div>
                  <span class="text-muted-foreground">Cost:</span>
                  <span class="ml-2 font-medium">${execution.cost_usd}</span>
                </div>
                
                <Button 
                  size="sm" 
                  variant="outline"
                  onclick={() => router.visit(`/executions/${execution.id}`)}
                >
                  View Details
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
      {/each}
    </div>
  </div>
</div>
```

## Verification Checklist

- [ ] Execution resource created
- [ ] LLM client working
- [ ] Agent executor job runs
- [ ] Executions tracked in DB
- [ ] Metrics calculated correctly
- [ ] Workflow engine functional
- [ ] Execution UI displays data
- [ ] Logs viewable

## Next Phase

**Phase 5: API, SDK & Developer Tools**

---

**Completion Status:** Phase 4 implements agent execution and workflows.
