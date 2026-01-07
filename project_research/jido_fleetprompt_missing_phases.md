# Jido Framework Analysis for FleetPrompt
## Missing Phases & Advanced Architecture Patterns

**Analysis Date:** January 2026  
**Source:** Jido v1.2.0 + Jido AI v0.5.2  
**Purpose:** Identify architectural gaps in FleetPrompt project phases based on Jido's proven patterns

---

## Executive Summary

After analyzing Jido's architecture (an autonomous agent framework for Elixir), I've identified **7 critical phases/concepts missing** from your original FleetPrompt project plan. Jido provides a battle-tested reference implementation that reveals sophisticated patterns for building production-grade agent systems.

### What is Jido?

Jido (自動 - "automatic" in Japanese) is a toolkit for building autonomous, distributed agent systems in Elixir. It's relevant to FleetPrompt because:

1. **Built on Phoenix/Elixir** (same stack as FleetPrompt)
2. **Agent-first architecture** (packages = agents in FleetPrompt)
3. **Production-ready patterns** (supervision, state management, error handling)
4. **Separation of concerns** (Actions, Agents, Sensors, Signals, Skills)
5. **AI-agnostic core** (Jido AI is separate package, like FleetPrompt's approach)

---

## Jido's Core Architecture (What FleetPrompt Can Learn From)

### The 6 Core Primitives

| Primitive | Purpose | FleetPrompt Equivalent |
|-----------|---------|----------------------|
| **Actions** | Discrete, composable units of work | Individual package functions/tools |
| **Agents** | Stateful entities that orchestrate actions | Running package instances |
| **Sensors** | Real-time data monitoring/collection | Package telemetry, health checks |
| **Signals** | CloudEvents-compliant message envelopes | Event bus, package communication |
| **Skills** | Modular capabilities attached to agents | Package categories/domains |
| **Workflows** | Action chains with error handling | Package execution pipelines |

---

## MISSING PHASE 1: Signal Architecture (Event System)

### What's Missing in FleetPrompt

Your current architecture likely uses direct function calls or simple PubSub. Jido uses a sophisticated **Signal system** based on CloudEvents v1.0.2 specification.

### What Signals Provide

```elixir
# Jido Signal Structure
%Jido.Signal{
  id: "uuid-here",                    # Unique signal ID
  type: "package.real_estate.lead_qualified",  # Hierarchical type
  source: "/packages/lead-qualification",      # Origin
  data: %{...},                       # Actual payload
  time: "2026-01-05T10:00:00Z",      # Timestamp
  subject: "user-123",                # What it's about
  extensions: %{                      # Custom metadata
    tenant_id: "tenant-456",
    priority: :high,
    retry_count: 0
  }
}
```

### Why FleetPrompt Needs This

**Current State:** Packages probably communicate via direct calls or basic PubSub:
```elixir
# Likely current approach
PackageA.process(data)
|> PackageB.enrich()
|> PackageC.notify()
```

**Problem:**
- ❌ No event trace (can't debug "why did this happen?")
- ❌ No replay capability (can't re-run failed events)
- ❌ Hard to add observability
- ❌ Tight coupling between packages

**With Signal Architecture:**
```elixir
# New approach with signals
{:ok, signal} = Signal.new(
  "lead.qualified",
  %{lead_id: "123", score: 95},
  source: "/packages/lead-qualification",
  subject: "tenant-#{tenant_id}"
)

# Publish to bus - multiple packages can subscribe
Signal.Bus.publish(:fleetprompt_bus, [signal])
```

**Benefits:**
- ✅ **Full event trace** (see every signal that triggered actions)
- ✅ **Replay failed events** (debugging, testing)
- ✅ **Loose coupling** (packages don't know about each other)
- ✅ **Multi-tenant isolation** (signals carry tenant context)
- ✅ **CloudEvents standard** (interop with external systems)

### Implementation Phase for FleetPrompt

**Phase 4.5: Signal Architecture Implementation** (2-3 weeks)

**Week 1: Core Signal System**
- [ ] Add `jido_signal` dependency
- [ ] Define FleetPrompt signal types (hierarchical)
  - `fleetprompt.package.*.started`
  - `fleetprompt.package.*.completed`
  - `fleetprompt.package.*.failed`
  - `fleetprompt.user.*.action`
  - `fleetprompt.tenant.*.event`
- [ ] Implement Signal Bus in main supervision tree
- [ ] Create base Signal modules for common events

**Week 2: Package Signal Integration**
- [ ] Refactor packages to emit signals instead of direct calls
- [ ] Add signal subscription patterns for package chaining
- [ ] Implement signal routing (what subscribes to what)
- [ ] Add signal middleware (auth, rate limiting, logging)

**Week 3: Observability & Tooling**
- [ ] Build signal inspector UI (LiveView dashboard)
- [ ] Add signal replay capability (for debugging)
- [ ] Implement signal persistence (Postgres table)
- [ ] Add signal search/filter UI

**Signal Type Hierarchy for FleetPrompt:**

```
fleetprompt.
├── package.
│   ├── real_estate.
│   │   ├── lead_qualification.qualified
│   │   ├── lead_qualification.failed
│   │   ├── mls_analysis.completed
│   │   └── property_research.started
│   ├── field_service.
│   │   ├── call_answering.call_received
│   │   ├── booking.appointment_scheduled
│   │   └── dispatch.tech_assigned
│   └── consultant.
│       ├── proposal.generated
│       └── client_research.completed
├── user.
│   ├── authentication.logged_in
│   ├── package.purchased
│   └── subscription.cancelled
└── system.
    ├── marketplace.package_published
    ├── billing.payment_processed
    └── telemetry.metric_recorded
```

---

## MISSING PHASE 2: Skills System (Package Composition)

### What's Missing

Your current plan likely has packages as standalone units. Jido has **Skills** - modular capabilities that can be composed.

### Jido's Skills Concept

```elixir
defmodule Jido.Skills.WeatherSkill do
  use Jido.Skill,
    name: "weather_skill",
    description: "Weather data and alerts",
    signal_patterns: ["weather.*"],  # What signals this skill handles
    schema_key: :weather             # State namespace

  # Define child processes this skill needs
  def child_spec(config) do
    [
      {WeatherAPI.Sensor, interval: :timer.minutes(15)},
      {WeatherAlerts.Monitor, config: config.alerts}
    ]
  end

  # Route signals to actions
  def router do
    [
      {"weather.fetch", %Instruction{action: Actions.FetchWeather}},
      {"weather.alert.*", %Instruction{action: Actions.ProcessAlert}}
    ]
  end

  # Initial state for this skill
  def initial_state do
    %{last_check: nil, cached_forecasts: %{}}
  end
end
```

### How This Applies to FleetPrompt

**Packages Should Be Skills:**

Instead of:
```elixir
# Monolithic package
defmodule FleetPrompt.Packages.LeadQualification do
  # Everything in one module
end
```

Do this:
```elixir
# Skill-based package
defmodule FleetPrompt.Skills.LeadQualificationSkill do
  use FleetPrompt.Skill,
    name: "lead_qualification",
    vertical: :real_estate,
    signal_patterns: [
      "lead.received.*",
      "lead.enriched.*"
    ]

  # This skill needs these child processes
  def child_spec(config) do
    [
      {FleetPrompt.Integrations.ZillowSensor, config: config.zillow},
      {FleetPrompt.Integrations.RealtorSensor, config: config.realtor},
      {FleetPrompt.Cache.LeadScorer, ttl: :timer.minutes(60)}
    ]
  end

  # Route signals to actions
  def router do
    [
      {"lead.received.zillow", %Instruction{
        action: Actions.QualifyZillowLead
      }},
      {"lead.received.realtor", %Instruction{
        action: Actions.QualifyRealtorLead
      }},
      {"lead.enriched.*", %Instruction{
        action: Actions.NotifyAgent
      }}
    ]
  end

  def initial_state do
    %{
      qualified_count: 0,
      average_score: 0.0,
      last_lead: nil
    }
  end
end
```

### Why Skills Matter for FleetPrompt

**Benefits:**
- ✅ **Composability:** Skills can be combined (LeadQual + MLSAnalysis)
- ✅ **State management:** Each skill manages its own state namespace
- ✅ **Child processes:** Skills can spawn necessary workers/sensors
- ✅ **Signal routing:** Skills declaratively define what they handle
- ✅ **Marketplace-ready:** Skills are self-contained, publishable units

### Implementation Phase for FleetPrompt

**Phase 5.5: Skills System Refactor** (3-4 weeks)

**Week 1: Skills Foundation**
- [ ] Create `FleetPrompt.Skill` behavior (similar to Jido.Skill)
- [ ] Define skill lifecycle (mount, router, initial_state, child_spec)
- [ ] Implement skill registry (track loaded skills)
- [ ] Add skill supervision tree integration

**Week 2: Package → Skill Migration**
- [ ] Refactor one package to skill pattern (proof of concept)
- [ ] Create skill state management (ETS or GenServer)
- [ ] Implement signal routing within skills
- [ ] Add skill configuration schema

**Week 3: Skill Composition**
- [ ] Build skill composition patterns (one skill uses another)
- [ ] Add skill dependency resolution
- [ ] Implement skill versioning
- [ ] Create skill conflict detection

**Week 4: Marketplace Integration**
- [ ] Update marketplace to publish/install skills
- [ ] Add skill compatibility checking
- [ ] Implement skill enable/disable per tenant
- [ ] Build skill management UI

**Skill Structure for FleetPrompt Packages:**

```elixir
defmodule FleetPrompt.Skills.RealEstate.LeadQualification do
  use FleetPrompt.Skill,
    # Metadata
    name: "lead_qualification",
    description: "Qualify and score real estate leads",
    category: :real_estate,
    version: "1.0.0",
    author: "FleetPrompt",
    
    # What signals this skill handles
    signal_patterns: [
      "lead.received.*",     # Any lead source
      "lead.manual.submit"   # Manual lead entry
    ],
    
    # Configuration schema
    config_schema: [
      min_score: [type: :integer, default: 70],
      auto_notify: [type: :boolean, default: true],
      zillow_api_key: [type: :string, required: true]
    ],
    
    # State namespace (stored in agent state under this key)
    state_key: :lead_qual

  # Child processes (sensors, workers, caches)
  def child_spec(config) do
    [
      {ZillowSensor, config: config},
      {LeadScoreCache, ttl: :timer.hours(1)}
    ]
  end

  # Signal → Action routing
  def router do
    [
      %{
        signal: "lead.received.zillow",
        action: Actions.QualifyZillowLead,
        priority: 100
      },
      %{
        signal: "lead.received.realtor",
        action: Actions.QualifyRealtorLead,
        priority: 100
      },
      %{
        signal: "lead.enriched.*",
        action: Actions.NotifyAgent,
        priority: 50,
        condition: fn signal, state ->
          # Only notify if score meets threshold
          signal.data.score >= state.config.min_score
        end
      }
    ]
  end

  # Initial state for this skill
  def initial_state do
    %{
      total_leads: 0,
      qualified_leads: 0,
      average_score: 0.0,
      last_qualified_at: nil
    }
  end

  # State transformation after action execution
  def transform_state(state, action_result) do
    case action_result do
      {:qualified, score} ->
        %{state |
          total_leads: state.total_leads + 1,
          qualified_leads: state.qualified_leads + 1,
          average_score: calculate_new_average(state, score),
          last_qualified_at: DateTime.utc_now()
        }
      
      {:disqualified, _reason} ->
        %{state | total_leads: state.total_leads + 1}
      
      _ ->
        state
    end
  end
end
```

---

## MISSING PHASE 3: Directives System (Agent Self-Modification)

### What's Missing

Jido has a **Directives** system that allows agents to modify themselves at runtime. This is crucial for adaptive agents.

### What Are Directives?

Directives are special actions that modify the agent itself (not just data):

```elixir
defmodule Jido.Actions.Directives.RegisterAction do
  use Jido.Action,
    name: "register_action",
    description: "Dynamically register a new action with the agent"

  def run(%{action_module: module}, context) do
    # Agent modifies itself to learn new capability
    {:ok, agent} = Jido.Agent.register_action(context.agent, module)
    
    {:ok, %{
      registered: module,
      total_actions: length(agent.actions)
    }}
  end
end
```

### How FleetPrompt Can Use Directives

**Use Case: Marketplace Package Installation**

When user buys a new package from marketplace:

```elixir
# Without Directives (current approach probably)
# 1. Download package code
# 2. Restart server to load new package
# 3. User waits 30+ seconds

# With Directives (Jido-inspired)
# 1. Send directive to running agent
# 2. Agent hot-loads new package
# 3. Immediately available (zero downtime)

Signal.new(
  "package.install",
  %{package_id: "mls-analysis-pro", version: "2.0.0"},
  source: "/marketplace"
)
|> Signal.Bus.publish()

# Agent receives signal, executes RegisterPackage directive
# Package is now available without restart!
```

### Common Directives FleetPrompt Needs

**System Directives:**
1. `RegisterPackage` - Hot-load new package
2. `UnregisterPackage` - Remove package from agent
3. `UpdatePackageConfig` - Change package settings at runtime
4. `EnableSkill` / `DisableSkill` - Turn skills on/off
5. `SetRateLimit` - Adjust API rate limits dynamically
6. `UpdateIntegration` - Change API keys/credentials without restart

**User Directives:**
7. `PauseAgent` - Stop processing new requests
8. `ResumeAgent` - Resume after pause
9. `ClearState` - Reset agent state
10. `ExportState` - Dump agent state for debugging

### Implementation Phase for FleetPrompt

**Phase 6.5: Directives System** (2 weeks)

**Week 1: Core Directives**
- [ ] Create `FleetPrompt.Directive` behavior
- [ ] Implement `RegisterPackage` directive
- [ ] Implement `UnregisterPackage` directive
- [ ] Implement `UpdateConfig` directive
- [ ] Add directive validation (can user perform this?)

**Week 2: Advanced Directives**
- [ ] Implement `PauseAgent` / `ResumeAgent`
- [ ] Implement `EnableSkill` / `DisableSkill`
- [ ] Add directive UI (buttons in package management)
- [ ] Implement directive audit log (who did what, when)

**Directive Example:**

```elixir
defmodule FleetPrompt.Directives.RegisterPackage do
  use FleetPrompt.Directive,
    name: "register_package",
    description: "Dynamically add a new package to the agent",
    requires_permission: :admin,
    schema: [
      package_id: [type: :string, required: true],
      version: [type: :string, default: "latest"]
    ]

  def run(%{package_id: package_id, version: version}, context) do
    agent = context.agent
    tenant_id = context.tenant_id

    with {:ok, package_module} <- Marketplace.fetch_package(package_id, version),
         {:ok, validated} <- validate_package_compatibility(agent, package_module),
         {:ok, updated_agent} <- Agent.register_package(agent, package_module) do
      
      # Emit signal for audit trail
      Signal.new(
        "agent.package_registered",
        %{package: package_id, version: version},
        source: "/directives/register_package",
        subject: "tenant-#{tenant_id}"
      )
      |> Signal.Bus.publish()

      {:ok, %{
        message: "Package #{package_id} v#{version} registered",
        total_packages: length(updated_agent.packages)
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_package_compatibility(agent, package_module) do
    # Check dependencies, conflicts, etc.
    :ok
  end
end
```

---

## MISSING PHASE 4: Comprehensive Testing Strategy (Jido's Approach)

### What's Missing

Jido has sophisticated testing helpers that make agent testing trivial. FleetPrompt needs similar patterns.

### Jido's Testing Philosophy

```elixir
defmodule MyApp.TaskAgentTest do
  use ExUnit.Case
  use Jido.Test.AgentCase  # Provides testing helpers

  describe "state transitions" do
    test "allows valid transitions" do
      # Start supervised agent for testing
      {:ok, agent} = start_supervised_agent(
        TaskAgent,
        id: "test-1",
        name: "Test Task"
      )

      # Test state transitions
      assert {:ok, %{status: :running}} =
        Jido.Agent.cmd(agent, StartTask, %{})

      assert {:ok, %{status: :completed}} =
        Jido.Agent.cmd(agent, CompleteTask, %{})
    end

    test "prevents invalid transitions" do
      {:ok, agent} = start_supervised_agent(TaskAgent, id: "test-2")

      # This should fail - can't complete without starting
      assert {:error, :invalid_transition} =
        Jido.Agent.cmd(agent, CompleteTask, %{})
    end
  end
end
```

### FleetPrompt Testing Layers

**Layer 1: Action Testing** (unit tests)
```elixir
defmodule FleetPrompt.Actions.QualifyLeadTest do
  use FleetPrompt.ActionCase

  test "qualifies high-value lead" do
    params = %{
      name: "John Doe",
      budget: 500_000,
      timeline: "immediate",
      pre_approved: true
    }

    assert {:ok, result} = QualifyLead.run(params, %{})
    assert result.score >= 90
    assert result.priority == :high
  end

  test "rejects spam lead" do
    params = %{name: "asdf", budget: 0}
    
    assert {:error, :invalid_lead} = QualifyLead.run(params, %{})
  end
end
```

**Layer 2: Workflow Testing** (integration tests)
```elixir
defmodule FleetPrompt.Workflows.LeadProcessingTest do
  use FleetPrompt.WorkflowCase

  test "complete lead qualification workflow" do
    lead = %{source: "zillow", id: "123"}

    {:ok, result} = FleetPrompt.Workflow.Chain.chain([
      Actions.FetchLeadDetails,
      Actions.EnrichWithMLS,
      Actions.QualifyLead,
      Actions.NotifyAgent
    ], lead)

    assert result.qualified == true
    assert result.notification_sent == true
  end

  test "workflow handles missing data gracefully" do
    incomplete_lead = %{source: "manual"}

    assert {:error, :missing_required_data} =
      FleetPrompt.Workflow.Chain.chain([
        Actions.QualifyLead
      ], incomplete_lead)
  end
end
```

**Layer 3: Package/Skill Testing** (end-to-end)
```elixir
defmodule FleetPrompt.Skills.LeadQualificationTest do
  use FleetPrompt.SkillCase

  setup do
    # Start skill with test configuration
    {:ok, skill} = start_supervised_skill(
      LeadQualificationSkill,
      config: %{
        min_score: 70,
        zillow_api_key: "test-key"
      }
    )

    %{skill: skill}
  end

  test "processes zillow lead signal", %{skill: skill} do
    signal = Signal.new(
      "lead.received.zillow",
      %{lead_id: "123", source: "zillow"}
    )

    # Publish signal to skill
    {:ok, _} = Skill.handle_signal(skill, signal)

    # Verify state updated
    state = Skill.get_state(skill, :lead_qual)
    assert state.total_leads == 1
  end
end
```

**Layer 4: Multi-Tenant Testing**
```elixir
defmodule FleetPrompt.MultiTenantTest do
  use FleetPrompt.SkillCase

  test "tenant isolation" do
    # Start agents for two tenants
    {:ok, agent_a} = start_tenant_agent("tenant-a")
    {:ok, agent_b} = start_tenant_agent("tenant-b")

    # Tenant A qualifies lead
    Signal.new("lead.received", %{id: "123"}, subject: "tenant-a")
    |> Signal.Bus.publish()

    # Verify only agent_a processed it
    assert Skill.get_state(agent_a, :lead_qual).total_leads == 1
    assert Skill.get_state(agent_b, :lead_qual).total_leads == 0
  end
end
```

### Implementation Phase for FleetPrompt

**Phase 7.5: Testing Infrastructure** (2 weeks)

**Week 1: Test Helpers**
- [ ] Create `FleetPrompt.ActionCase` (action testing helper)
- [ ] Create `FleetPrompt.WorkflowCase` (workflow testing)
- [ ] Create `FleetPrompt.SkillCase` (skill/package testing)
- [ ] Create `FleetPrompt.SignalCase` (signal testing)

**Week 2: Test Coverage**
- [ ] Write tests for all existing packages
- [ ] Add property-based tests (StreamData)
- [ ] Implement multi-tenant test scenarios
- [ ] Add performance benchmarks

---

## MISSING PHASE 5: Observability & Telemetry (Production-Ready Monitoring)

### What's Missing

Jido has built-in telemetry events. FleetPrompt needs comprehensive observability.

### Jido's Telemetry Events

```elixir
# Jido emits telemetry for:
[:jido, :action, :start]         # Action execution started
[:jido, :action, :stop]          # Action completed
[:jido, :action, :exception]     # Action failed
[:jido, :workflow, :start]       # Workflow started
[:jido, :workflow, :stop]        # Workflow completed
[:jido, :agent, :state_change]   # Agent state changed
[:jido, :signal, :published]     # Signal published to bus
[:jido, :signal, :delivered]     # Signal delivered to subscriber
```

### FleetPrompt Telemetry Events Needed

**Package Events:**
```elixir
[:fleetprompt, :package, :start]        # Package execution started
[:fleetprompt, :package, :stop]         # Package completed
[:fleetprompt, :package, :exception]    # Package failed
[:fleetprompt, :package, :timeout]      # Package timed out
[:fleetprompt, :package, :retry]        # Package retrying
```

**User Events:**
```elixir
[:fleetprompt, :user, :package_purchased]
[:fleetprompt, :user, :subscription_created]
[:fleetprompt, :user, :limit_exceeded]
[:fleetprompt, :user, :api_key_used]
```

**System Events:**
```elixir
[:fleetprompt, :marketplace, :package_published]
[:fleetprompt, :billing, :payment_processed]
[:fleetprompt, :cache, :hit]
[:fleetprompt, :cache, :miss]
[:fleetprompt, :rate_limit, :exceeded]
```

### Telemetry Handlers

**Performance Monitoring:**
```elixir
defmodule FleetPrompt.Telemetry.Performance do
  def attach do
    :telemetry.attach_many(
      "fleetprompt-performance",
      [
        [:fleetprompt, :package, :stop],
        [:fleetprompt, :workflow, :stop]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:fleetprompt, :package, :stop], measurements, metadata, _config) do
    duration = measurements.duration
    package = metadata.package

    # Send to metrics system
    Metrics.histogram("package.duration", duration, tags: [package: package])

    # Alert if slow
    if duration > 5_000_000_000 do  # 5 seconds in nanoseconds
      Alert.slow_package(package, duration)
    end
  end
end
```

**Business Metrics:**
```elixir
defmodule FleetPrompt.Telemetry.BusinessMetrics do
  def attach do
    :telemetry.attach_many(
      "fleetprompt-business",
      [
        [:fleetprompt, :user, :package_purchased],
        [:fleetprompt, :package, :stop]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:fleetprompt, :user, :package_purchased], _measurements, metadata, _config) do
    Metrics.increment("revenue.package_sold", 
      tags: [
        package: metadata.package_id,
        vertical: metadata.vertical,
        price: metadata.price
      ]
    )
  end
end
```

### Implementation Phase for FleetPrompt

**Phase 8.5: Telemetry & Observability** (2 weeks)

**Week 1: Telemetry Events**
- [ ] Define all telemetry events (50+ events)
- [ ] Emit events from actions, workflows, packages
- [ ] Create telemetry handlers (performance, business, errors)
- [ ] Integrate with metrics backend (Prometheus, DataDog, etc)

**Week 2: Observability UI**
- [ ] Build telemetry dashboard (LiveView)
- [ ] Add real-time metrics charts
- [ ] Implement alert rules
- [ ] Create performance debugging tools

---

## MISSING PHASE 6: Distributed Agent System (Multi-Node Architecture)

### What's Missing

Jido is built for distributed Elixir. FleetPrompt needs multi-node patterns for scale.

### Why Distributed Matters for FleetPrompt

**Single Node Limits:**
- 1 server = ~50,000 concurrent package executions (Phoenix limit)
- No redundancy (server restart = downtime)
- Regional latency (users far from server)

**Multi-Node Benefits:**
- Horizontal scaling (add servers as needed)
- Geographic distribution (EU server, US server, APAC server)
- Zero-downtime deployments (rolling updates)
- Fault tolerance (one node crashes, others continue)

### Jido's Distributed Patterns

**1. Agent Registry (Global Process Registry)**
```elixir
# Start agent on any node, find from any node
{:ok, agent} = MyAgent.start_link(id: "unique-id")

# From any other node in cluster
{:ok, agent} = Jido.get_agent("unique-id")
```

**2. Signal Bus (Cross-Node Events)**
```elixir
# Publish signal on Node A
Signal.new("event", %{data: "value"})
|> Signal.Bus.publish()

# Subscriber on Node B receives it (automatically)
```

**3. Distributed Supervision**
```elixir
# Agents distributed across nodes via Horde
# If node crashes, agents restart on other nodes automatically
```

### FleetPrompt Distributed Architecture

**Scenario: User has package running, server needs to restart**

**Without distribution:**
1. Server restart
2. User's package execution stops
3. User sees error, tries again
4. Bad experience

**With distribution:**
1. User's package runs on Node A
2. Node A needs restart (deployment)
3. Package migrated to Node B (automatically via Horde)
4. User sees nothing, package continues
5. Node A restarts, rejoins cluster
6. Zero downtime

### Implementation Phase for FleetPrompt

**Phase 9.5: Distributed System** (4 weeks)

**Week 1: Cluster Setup**
- [ ] Add libcluster for auto-clustering
- [ ] Configure cluster topology (DNS, Kubernetes, etc)
- [ ] Add distributed registry (Horde.Registry)
- [ ] Add distributed supervisor (Horde.DynamicSupervisor)

**Week 2: Distributed Agents**
- [ ] Migrate package processes to distributed supervision
- [ ] Implement process handoff (node A → node B)
- [ ] Add health checks, node monitoring
- [ ] Test failover scenarios

**Week 3: Distributed Signals**
- [ ] Ensure Signal Bus works cross-node
- [ ] Add eventual consistency handling
- [ ] Implement distributed locks (for conflicts)
- [ ] Add partition tolerance

**Week 4: Multi-Region Deployment**
- [ ] Deploy to 2+ regions (us-east, eu-west)
- [ ] Add region-aware routing (users → nearest node)
- [ ] Implement global rate limiting (distributed counter)
- [ ] Add cross-region monitoring

---

## MISSING PHASE 7: Schema Evolution & Versioning

### What's Missing

Jido has versioning built-in. FleetPrompt needs package versioning strategy.

### Package Versioning Strategy

**Problem:**
- User has LeadQual v1.0 installed
- You release LeadQual v2.0 with breaking changes
- User's workflows break on auto-update

**Solution: Semantic Versioning + Compatibility Layer**

```elixir
defmodule FleetPrompt.Packages.LeadQualification do
  use FleetPrompt.Package,
    name: "lead_qualification",
    version: "2.0.0",  # Major.Minor.Patch
    backward_compatible_with: ["1.5.0", "1.6.0", "1.7.0"],
    schema_version: 2

  # v2 schema
  def schema do
    [
      lead_id: [type: :string, required: true],
      source: [type: :string, required: true],
      # NEW in v2.0
      enrichment_level: [
        type: {:enum, [:basic, :standard, :premium]},
        default: :standard
      ]
    ]
  end

  # Compatibility adapter for v1 → v2
  def migrate_from_v1(v1_params) do
    # Old v1 had boolean "enrich" flag
    # New v2 has enum "enrichment_level"
    enrichment_level = if v1_params[:enrich], do: :premium, else: :basic

    v1_params
    |> Map.delete(:enrich)
    |> Map.put(:enrichment_level, enrichment_level)
  end

  def run(params, context) do
    # Detect version from context
    params = case context.package_version do
      "1." <> _ -> migrate_from_v1(params)
      "2." <> _ -> params
    end

    # ... actual logic
  end
end
```

### Implementation Phase for FleetPrompt

**Phase 10.5: Schema Evolution** (2 weeks)

**Week 1: Versioning System**
- [ ] Add version tracking to packages
- [ ] Implement backward compatibility checks
- [ ] Create migration system (v1 → v2 → v3)
- [ ] Add deprecation warnings

**Week 2: Marketplace Versioning**
- [ ] Support multiple package versions in marketplace
- [ ] Allow users to pin version ("stay on v1.5")
- [ ] Add auto-update settings (major/minor/patch)
- [ ] Implement rollback (revert to previous version)

---

## Implementation Roadmap: All Missing Phases

### Quick Wins (Week 1-2)
1. **Telemetry Events** - Easy to add, huge value
2. **Testing Helpers** - Immediate productivity boost

### Core Architecture (Month 1-2)
3. **Signal Architecture** - Foundation for everything else
4. **Skills System** - Refactor packages to skills
5. **Directives** - Hot-loading packages

### Production Ready (Month 3)
6. **Distributed System** - Scale and fault tolerance
7. **Schema Evolution** - Handle upgrades gracefully

---

## Summary: What You're Missing

| Missing Phase | Impact if Skipped | Effort | Priority |
|--------------|-------------------|--------|----------|
| **Signal Architecture** | Hard to debug, tightly coupled | 3 weeks | HIGH |
| **Skills System** | Packages not composable | 4 weeks | HIGH |
| **Directives** | Require restarts for updates | 2 weeks | MEDIUM |
| **Testing Strategy** | Bugs in production | 2 weeks | HIGH |
| **Telemetry** | Blind to performance issues | 2 weeks | HIGH |
| **Distributed System** | Can't scale beyond 1 server | 4 weeks | MEDIUM |
| **Versioning** | Break user workflows on update | 2 weeks | MEDIUM |

**Total Additional Time:** ~19 weeks (5 months) to reach Jido-level maturity

**Recommendation:** 
- **Phase 1-3:** Add to MVP (Signals, Skills, Testing) - **Critical**
- **Phase 4-5:** Add to Month 6-12 roadmap (Telemetry, Directives)
- **Phase 6-7:** Add to Year 2+ (Distributed, Versioning)

---

## Next Document

See **Part 2** for detailed implementation guides and code examples for each missing phase.
