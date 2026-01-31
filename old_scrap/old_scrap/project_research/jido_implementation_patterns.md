# Jido Implementation Patterns for FleetPrompt
## Part 2: Detailed Code Examples & Architecture Patterns

**Analysis Date:** January 2026  
**Source:** Jido v1.2.0 Framework Patterns  

---

## Table of Contents

1. [Signal-Based Package Communication](#signal-based-package-communication)
2. [State Management Patterns](#state-management-patterns)
3. [Error Handling & Compensation](#error-handling--compensation)
4. [Supervision Tree Architecture](#supervision-tree-architecture)
5. [Testing Patterns](#testing-patterns)
6. [Performance Optimization](#performance-optimization)
7. [Security & Multi-Tenancy](#security--multi-tenancy)

---

## 1. Signal-Based Package Communication

### Pattern: Event-Driven Package Chains

**Problem:** Packages need to trigger each other without tight coupling.

**Jido Pattern:**
```elixir
# Package A emits signal when done
defmodule Packages.LeadQualification do
  def run(params, context) do
    # ... qualify lead ...
    
    # Emit signal for next package
    {:ok, _} = Signal.new(
      "lead.qualified",
      %{lead_id: lead.id, score: 95, priority: :high},
      source: "/packages/lead-qualification",
      subject: "tenant-#{context.tenant_id}"
    )
    |> Signal.Bus.publish()
    
    {:ok, %{qualified: true, score: 95}}
  end
end

# Package B subscribes to signal
defmodule Packages.MLSEnrichment do
  def mount(opts) do
    # Subscribe to qualified leads
    {:ok, _sub_id} = Signal.Bus.subscribe(
      :fleetprompt_bus,
      "lead.qualified",
      dispatch: {:module, target: __MODULE__, function: :handle_signal}
    )
    
    {:ok, opts}
  end

  def handle_signal(%Signal{data: %{lead_id: id, score: score}}) when score >= 90 do
    # Only enrich high-value leads
    enrich_lead(id)
  end
  
  def handle_signal(_signal), do: :ok  # Ignore low-score leads
end
```

**Benefits:**
- ✅ Loose coupling (packages don't reference each other)
- ✅ Conditional routing (only high-score leads get enriched)
- ✅ Multi-subscriber (multiple packages can listen to same signal)
- ✅ Full audit trail (see all signals that led to outcome)

---

### Pattern: Signal Middleware Stack

**Use Case:** Apply auth, rate limiting, logging to all signals.

```elixir
defmodule FleetPrompt.Signal.Middleware do
  # Middleware pipeline: auth → rate_limit → log → dispatch
  def call(signal, pipeline) do
    pipeline
    |> Enum.reduce({:ok, signal}, fn
      middleware, {:ok, signal} -> middleware.call(signal)
      _middleware, {:error, reason} -> {:error, reason}
    end)
  end
end

defmodule FleetPrompt.Signal.Middleware.Auth do
  def call(signal) do
    tenant_id = Signal.get_extension(signal, "tenant_id")
    
    case FleetPrompt.Tenants.authorized?(tenant_id, signal.type) do
      true -> {:ok, signal}
      false -> {:error, :unauthorized}
    end
  end
end

defmodule FleetPrompt.Signal.Middleware.RateLimit do
  def call(signal) do
    tenant_id = Signal.get_extension(signal, "tenant_id")
    
    case FleetPrompt.RateLimit.check(tenant_id, signal.type) do
      :ok -> {:ok, signal}
      {:error, :rate_limited} -> {:error, :rate_limited}
    end
  end
end

# Apply middleware in Signal Bus
defmodule FleetPrompt.Application do
  def start(_type, _args) do
    children = [
      {Signal.Bus, 
        name: :fleetprompt_bus,
        middleware: [
          FleetPrompt.Signal.Middleware.Auth,
          FleetPrompt.Signal.Middleware.RateLimit,
          FleetPrompt.Signal.Middleware.Log,
          FleetPrompt.Signal.Middleware.Metrics
        ]
      }
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

---

### Pattern: Signal Replay (Debugging)

**Use Case:** User reports "package didn't trigger". Replay signals to debug.

```elixir
defmodule FleetPrompt.SignalReplay do
  # Store signals in Postgres
  def persist_signal(signal) do
    Repo.insert!(%SignalLog{
      id: signal.id,
      type: signal.type,
      data: signal.data,
      tenant_id: Signal.get_extension(signal, "tenant_id"),
      inserted_at: DateTime.utc_now()
    })
  end

  # Replay signal (for debugging)
  def replay(signal_id) do
    signal_log = Repo.get!(SignalLog, signal_id)
    
    # Reconstruct signal from log
    {:ok, signal} = Signal.new(
      signal_log.type,
      signal_log.data,
      id: signal_log.id  # Same ID
    )
    
    # Publish again
    Signal.Bus.publish(:fleetprompt_bus, [signal])
  end

  # Replay all signals for tenant (testing)
  def replay_tenant(tenant_id, opts \\ []) do
    from_date = Keyword.get(opts, :from, ~D[2026-01-01])
    
    SignalLog
    |> where([s], s.tenant_id == ^tenant_id)
    |> where([s], s.inserted_at >= ^from_date)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
    |> Enum.each(&replay(&1.id))
  end
end
```

---

## 2. State Management Patterns

### Pattern: Namespaced State (Skills)

**Problem:** Multiple packages need separate state spaces without conflicts.

**Jido Pattern:**
```elixir
defmodule FleetPrompt.Agent do
  defstruct [
    :id,
    :tenant_id,
    state: %{
      # Each skill gets namespace
      lead_qualification: %{
        total_leads: 0,
        qualified_count: 0,
        average_score: 0.0
      },
      mls_enrichment: %{
        cache: %{},
        last_sync: nil
      },
      notification: %{
        queue: [],
        sent_count: 0
      }
    }
  ]
end

# Skills read/write to their namespace
defmodule Skills.LeadQualification do
  def run(params, context) do
    # Read current state
    state = get_in(context.agent.state, [:lead_qualification])
    
    # Update state
    new_state = %{state |
      total_leads: state.total_leads + 1,
      qualified_count: state.qualified_count + 1,
      average_score: calculate_average(state, params.score)
    }
    
    # Return state update
    {:ok, %{}, state_updates: [lead_qualification: new_state]}
  end
end
```

---

### Pattern: Transactional State Updates

**Use Case:** Multiple packages update state atomically (no partial updates).

```elixir
defmodule FleetPrompt.Agent.State do
  # Update multiple namespaces atomically
  def transactional_update(agent, updates) do
    # Use Agent (Elixir stdlib) for atomic updates
    Agent.update(agent.pid, fn state ->
      Enum.reduce(updates, state, fn {namespace, changes}, acc ->
        update_in(acc, [namespace], &Map.merge(&1, changes))
      end)
    end)
  end
end

# Usage in workflow
def workflow_run(agent) do
  # Gather all state changes
  updates = [
    lead_qualification: %{total_leads: +1},
    mls_enrichment: %{cache_hits: +1},
    billing: %{api_calls: +1}
  ]
  
  # Apply atomically (all or nothing)
  FleetPrompt.Agent.State.transactional_update(agent, updates)
end
```

---

### Pattern: State Snapshots (Time Travel Debugging)

**Use Case:** Debug "why did agent behave differently yesterday?"

```elixir
defmodule FleetPrompt.Agent.StateSnapshot do
  # Take snapshot of agent state
  def snapshot(agent) do
    Repo.insert!(%StateSnapshot{
      agent_id: agent.id,
      tenant_id: agent.tenant_id,
      state: agent.state,
      snapshot_at: DateTime.utc_now()
    })
  end

  # Restore agent to previous state
  def restore(agent, snapshot_id) do
    snapshot = Repo.get!(StateSnapshot, snapshot_id)
    
    Agent.update(agent.pid, fn _current_state ->
      snapshot.state
    end)
  end

  # Compare states (what changed?)
  def diff(snapshot_a_id, snapshot_b_id) do
    a = Repo.get!(StateSnapshot, snapshot_a_id)
    b = Repo.get!(StateSnapshot, snapshot_b_id)
    
    # Deep diff
    FleetPrompt.Utils.MapDiff.diff(a.state, b.state)
  end
end

# Automatic snapshots on package install/remove
defmodule FleetPrompt.Directives.RegisterPackage do
  def run(params, context) do
    # Snapshot before change
    before = FleetPrompt.Agent.StateSnapshot.snapshot(context.agent)
    
    # Make change
    {:ok, agent} = Agent.register_package(context.agent, params.package)
    
    # Snapshot after
    after = FleetPrompt.Agent.StateSnapshot.snapshot(agent)
    
    {:ok, %{before_snapshot: before.id, after_snapshot: after.id}}
  end
end
```

---

## 3. Error Handling & Compensation

### Pattern: Compensating Actions (Saga Pattern)

**Use Case:** Multi-step workflow fails partway - need to undo previous steps.

```elixir
defmodule FleetPrompt.Workflow.Saga do
  # Workflow with compensation
  def run_with_compensation(steps, params) do
    # Track completed steps for rollback
    completed = []
    
    result = Enum.reduce_while(steps, {:ok, params, completed}, fn
      {action, compensate}, {:ok, result, completed} ->
        case action.run(result, %{}) do
          {:ok, new_result} ->
            # Success, continue with compensation info
            {:cont, {:ok, new_result, [{action, compensate} | completed]}}
          
          {:error, reason} ->
            # Failure, stop and return error with rollback info
            {:halt, {:error, reason, completed}}
        end
    end)
    
    case result do
      {:ok, final_result, _completed} ->
        {:ok, final_result}
      
      {:error, reason, completed} ->
        # Rollback completed steps in reverse
        rollback(completed)
        {:error, reason}
    end
  end

  defp rollback(completed) do
    completed
    |> Enum.reverse()
    |> Enum.each(fn {_action, compensate} ->
      compensate.run(%{}, %{})
    end)
  end
end

# Usage
defmodule Workflows.PurchasePackage do
  def run(params) do
    FleetPrompt.Workflow.Saga.run_with_compensation([
      # Step 1: Charge card (compensate: refund)
      {Actions.ChargeCard, Actions.RefundCard},
      
      # Step 2: Register package (compensate: unregister)
      {Actions.RegisterPackage, Actions.UnregisterPackage},
      
      # Step 3: Send welcome email (compensate: send cancellation email)
      {Actions.SendWelcomeEmail, Actions.SendCancellationEmail}
    ], params)
  end
end
```

---

### Pattern: Circuit Breaker (External APIs)

**Use Case:** Zillow API is down, stop hammering it.

```elixir
defmodule FleetPrompt.CircuitBreaker do
  use GenServer

  # Circuit states: :closed (working), :open (failing), :half_open (testing)
  defstruct state: :closed, failures: 0, last_failure: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def call(breaker, fun) do
    case GenServer.call(breaker, :check_state) do
      :closed ->
        # Circuit closed, try request
        case fun.() do
          {:ok, result} ->
            GenServer.cast(breaker, :success)
            {:ok, result}
          
          {:error, reason} ->
            GenServer.cast(breaker, :failure)
            {:error, reason}
        end
      
      :open ->
        # Circuit open, don't try request
        {:error, :circuit_open}
      
      :half_open ->
        # Testing if service recovered
        case fun.() do
          {:ok, result} ->
            GenServer.cast(breaker, :success)
            {:ok, result}
          
          {:error, reason} ->
            GenServer.cast(breaker, :failure)
            {:error, reason}
        end
    end
  end

  # GenServer callbacks
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  def handle_call(:check_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_cast(:success, state) do
    {:noreply, %{state | state: :closed, failures: 0}}
  end

  def handle_cast(:failure, state) do
    new_failures = state.failures + 1
    
    new_state = if new_failures >= 5 do
      # Open circuit after 5 failures
      Process.send_after(self(), :half_open, :timer.seconds(30))
      %{state | state: :open, failures: new_failures, last_failure: DateTime.utc_now()}
    else
      %{state | failures: new_failures}
    end
    
    {:noreply, new_state}
  end

  def handle_info(:half_open, state) do
    # Try to recover
    {:noreply, %{state | state: :half_open}}
  end
end

# Usage in package
defmodule Packages.ZillowIntegration do
  def fetch_lead(lead_id) do
    FleetPrompt.CircuitBreaker.call(:zillow_breaker, fn ->
      HTTPoison.get("https://api.zillow.com/leads/#{lead_id}")
    end)
  end
end
```

---

## 4. Supervision Tree Architecture

### Pattern: Dynamic Supervisor per Tenant

**Use Case:** Each tenant gets isolated supervision tree.

```elixir
# Top-level supervisor
defmodule FleetPrompt.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      # Tenant supervisor registry
      {DynamicSupervisor, name: FleetPrompt.TenantSupervisor, strategy: :one_for_one},
      
      # Global services
      FleetPrompt.Repo,
      {Signal.Bus, name: :fleetprompt_bus},
      FleetPrompt.Marketplace,
      FleetPrompt.Billing
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Start supervisor for each tenant
defmodule FleetPrompt.TenantManager do
  def start_tenant(tenant_id) do
    # Start supervision tree for tenant
    spec = {FleetPrompt.TenantSupervisor, tenant_id: tenant_id}
    DynamicSupervisor.start_child(FleetPrompt.TenantSupervisor, spec)
  end

  def stop_tenant(tenant_id) do
    # Find and stop tenant supervisor
    case Registry.lookup(FleetPrompt.TenantRegistry, tenant_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(FleetPrompt.TenantSupervisor, pid)
      [] -> {:error, :not_found}
    end
  end
end

# Tenant-specific supervisor
defmodule FleetPrompt.TenantSupervisor do
  use Supervisor

  def start_link(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    Supervisor.start_link(__MODULE__, tenant_id, name: via_tuple(tenant_id))
  end

  def init(tenant_id) do
    children = [
      # Tenant's agent
      {FleetPrompt.Agent, tenant_id: tenant_id},
      
      # Tenant's package processes
      {DynamicSupervisor, name: via_tuple({tenant_id, :packages}), strategy: :one_for_one},
      
      # Tenant's sensors
      {FleetPrompt.Sensors.Supervisor, tenant_id: tenant_id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(tenant_id) do
    {:via, Registry, {FleetPrompt.TenantRegistry, tenant_id}}
  end
end
```

---

### Pattern: Package Lifecycle Management

**Use Case:** Dynamically start/stop packages based on user subscriptions.

```elixir
defmodule FleetPrompt.PackageManager do
  # Start package for tenant
  def start_package(tenant_id, package_id, config) do
    # Get tenant's package supervisor
    supervisor = via_tuple({tenant_id, :packages})
    
    # Start package process
    spec = {
      FleetPrompt.Packages.Runner,
      tenant_id: tenant_id,
      package_id: package_id,
      config: config
    }
    
    DynamicSupervisor.start_child(supervisor, spec)
  end

  # Stop package
  def stop_package(tenant_id, package_id) do
    supervisor = via_tuple({tenant_id, :packages})
    
    # Find package process
    case Registry.lookup(FleetPrompt.PackageRegistry, {tenant_id, package_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(supervisor, pid)
      [] ->
        {:error, :not_running}
    end
  end

  # Restart package (upgrade)
  def restart_package(tenant_id, package_id, new_config) do
    with :ok <- stop_package(tenant_id, package_id),
         {:ok, _pid} <- start_package(tenant_id, package_id, new_config) do
      :ok
    end
  end

  defp via_tuple(name) do
    {:via, Registry, {FleetPrompt.TenantRegistry, name}}
  end
end
```

---

## 5. Testing Patterns

### Pattern: Property-Based Testing (StreamData)

**Use Case:** Test packages with thousands of random inputs.

```elixir
defmodule FleetPrompt.Packages.LeadQualificationTest do
  use ExUnit.Case
  use ExUnitProperties

  property "lead qualification always returns score 0-100" do
    check all name <- string(:alphanumeric),
              budget <- integer(0..10_000_000),
              timeline <- member_of(["immediate", "1-3 months", "3-6 months", "6+ months"]),
              pre_approved <- boolean() do
      
      params = %{
        name: name,
        budget: budget,
        timeline: timeline,
        pre_approved: pre_approved
      }

      {:ok, result} = Packages.LeadQualification.run(params, %{})

      assert result.score >= 0
      assert result.score <= 100
    end
  end

  property "high budget + immediate timeline + pre-approved = high score" do
    check all budget <- integer(500_000..10_000_000) do
      params = %{
        name: "Test Lead",
        budget: budget,
        timeline: "immediate",
        pre_approved: true
      }

      {:ok, result} = Packages.LeadQualification.run(params, %{})

      assert result.score >= 85
      assert result.priority == :high
    end
  end
end
```

---

### Pattern: Integration Test Helpers

```elixir
defmodule FleetPrompt.Test.PackageCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import FleetPrompt.Test.PackageCase
      alias FleetPrompt.{Repo, Packages}
    end
  end

  # Helper: Start package with test tenant
  def start_test_package(package_module, opts \\ []) do
    tenant = insert_test_tenant()
    config = Keyword.get(opts, :config, %{})
    
    {:ok, pid} = PackageManager.start_package(
      tenant.id,
      package_module.id(),
      config
    )
    
    %{tenant: tenant, package: pid, config: config}
  end

  # Helper: Emit test signal
  def emit_signal(type, data, opts \\ []) do
    {:ok, signal} = Signal.new(
      type,
      data,
      Keyword.merge([source: "/test"], opts)
    )
    
    Signal.Bus.publish(:fleetprompt_bus, [signal])
    
    # Wait for signal processing
    Process.sleep(100)
    
    signal
  end

  # Helper: Assert signal was emitted
  def assert_signal_emitted(type, timeout \\ 1000) do
    receive do
      {:signal, %Signal{type: ^type} = signal} -> signal
    after
      timeout -> flunk("Expected signal #{type} not emitted within #{timeout}ms")
    end
  end

  defp insert_test_tenant do
    Repo.insert!(%Tenant{
      id: Ecto.UUID.generate(),
      name: "Test Tenant #{System.unique_integer()}",
      status: :active
    })
  end
end

# Usage in tests
defmodule FleetPrompt.Packages.LeadQualificationIntegrationTest do
  use FleetPrompt.Test.PackageCase

  test "qualifies lead end-to-end" do
    %{tenant: tenant, package: package} = start_test_package(
      Packages.LeadQualification,
      config: %{min_score: 70}
    )

    # Emit lead received signal
    emit_signal(
      "lead.received.zillow",
      %{lead_id: "123", source: "zillow"},
      subject: "tenant-#{tenant.id}"
    )

    # Assert qualified signal emitted
    signal = assert_signal_emitted("lead.qualified")
    assert signal.data.score >= 70
  end
end
```

---

## 6. Performance Optimization

### Pattern: ETS Caching

**Use Case:** Cache API responses to avoid rate limits.

```elixir
defmodule FleetPrompt.Cache do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Create ETS table for cache
    table = :ets.new(:fleetprompt_cache, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    {:ok, %{table: table}}
  end

  def get(key) do
    case :ets.lookup(:fleetprompt_cache, key) do
      [{^key, value, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, value}
        else
          :ets.delete(:fleetprompt_cache, key)
          {:error, :expired}
        end
      
      [] ->
        {:error, :not_found}
    end
  end

  def put(key, value, ttl_seconds \\ 3600) do
    expires_at = DateTime.add(DateTime.utc_now(), ttl_seconds, :second)
    :ets.insert(:fleetprompt_cache, {key, value, expires_at})
    :ok
  end

  def delete(key) do
    :ets.delete(:fleetprompt_cache, key)
    :ok
  end
end

# Usage in package
defmodule Packages.MLSData do
  def fetch_property(mls_id) do
    cache_key = "mls:#{mls_id}"
    
    case FleetPrompt.Cache.get(cache_key) do
      {:ok, cached} ->
        # Cache hit
        {:ok, cached}
      
      {:error, _} ->
        # Cache miss, fetch from API
        case MLS.API.fetch(mls_id) do
          {:ok, data} ->
            # Store in cache (1 hour TTL)
            FleetPrompt.Cache.put(cache_key, data, 3600)
            {:ok, data}
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
```

---

### Pattern: Concurrent Task Execution

**Use Case:** Package needs to call 10 APIs - do it concurrently.

```elixir
defmodule Packages.PropertyResearch do
  def run(%{address: address}, _context) do
    # Run multiple API calls concurrently
    results = Task.async_stream(
      [
        {:zillow, fn -> fetch_zillow_data(address) end},
        {:realtor, fn -> fetch_realtor_data(address) end},
        {:public_records, fn -> fetch_public_records(address) end},
        {:tax_records, fn -> fetch_tax_records(address) end},
        {:permits, fn -> fetch_permits(address) end}
      ],
      fn {source, fun} ->
        case fun.() do
          {:ok, data} -> {source, data}
          {:error, _} -> {source, nil}
        end
      end,
      max_concurrency: 5,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Map.new()

    {:ok, results}
  end
end
```

---

## 7. Security & Multi-Tenancy

### Pattern: Row-Level Security with Ecto

**Use Case:** Ensure tenants can't access each other's data.

```elixir
defmodule FleetPrompt.Tenants.Scope do
  import Ecto.Query

  # Add tenant filter to all queries
  def scope(query, tenant_id) do
    from(q in query, where: q.tenant_id == ^tenant_id)
  end
end

# Usage in contexts
defmodule FleetPrompt.Packages do
  import FleetPrompt.Tenants.Scope

  def list_packages(tenant_id) do
    Package
    |> scope(tenant_id)
    |> Repo.all()
  end

  def get_package!(tenant_id, package_id) do
    Package
    |> scope(tenant_id)
    |> Repo.get!(package_id)
  end
end

# Enforce in Plug
defmodule FleetPrompt.Plugs.EnsureTenant do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant_id = get_session(conn, :tenant_id)
    
    case FleetPrompt.Tenants.get(tenant_id) do
      {:ok, tenant} ->
        assign(conn, :current_tenant, tenant)
      
      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> halt()
    end
  end
end
```

---

### Pattern: Rate Limiting per Tenant

```elixir
defmodule FleetPrompt.RateLimit do
  use GenServer

  # State: %{tenant_id => %{endpoint => {count, window_start}}}

  def check(tenant_id, endpoint, limit \\ 100, window \\ 60_000) do
    GenServer.call(__MODULE__, {:check, tenant_id, endpoint, limit, window})
  end

  def handle_call({:check, tenant_id, endpoint, limit, window}, _from, state) do
    key = {tenant_id, endpoint}
    now = System.system_time(:millisecond)
    
    case Map.get(state, key) do
      nil ->
        # First request in window
        new_state = Map.put(state, key, {1, now})
        {:reply, :ok, new_state}
      
      {count, window_start} ->
        if now - window_start > window do
          # New window
          new_state = Map.put(state, key, {1, now})
          {:reply, :ok, new_state}
        else
          if count < limit do
            # Within limit
            new_state = Map.put(state, key, {count + 1, window_start})
            {:reply, :ok, new_state}
          else
            # Rate limited
            {:reply, {:error, :rate_limited}, state}
          end
        end
    end
  end
end

# Usage in controller
defmodule FleetPrompt.API.PackageController do
  use FleetPrompt, :controller

  def execute(conn, %{"package" => package, "params" => params}) do
    tenant_id = conn.assigns.current_tenant.id
    
    case FleetPrompt.RateLimit.check(tenant_id, "package.execute", 1000, 60_000) do
      :ok ->
        # Execute package
        result = Packages.execute(package, params, tenant_id)
        json(conn, result)
      
      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Rate limit exceeded"})
    end
  end
end
```

---

## Summary: Key Patterns to Adopt

| Pattern | Impact | Complexity | Priority |
|---------|--------|------------|----------|
| **Signal-based communication** | Loose coupling, auditability | Medium | HIGH |
| **Namespaced state** | Clean state management | Low | HIGH |
| **Circuit breaker** | Resilience to API failures | Medium | HIGH |
| **Dynamic supervision** | Tenant isolation | Medium | MEDIUM |
| **ETS caching** | 10-100x performance | Low | HIGH |
| **Property-based testing** | Catch edge cases | Medium | MEDIUM |
| **Compensation sagas** | Reliable workflows | High | MEDIUM |
| **Row-level security** | Data isolation | Low | HIGH |

---

## Next Steps

1. **Start with signals** - Biggest architectural improvement
2. **Add ETS caching** - Easy performance win
3. **Implement dynamic supervision** - Enables hot-loading packages
4. **Build comprehensive tests** - Prevents regressions

Every pattern here is proven in production Jido deployments. Adopt incrementally.
