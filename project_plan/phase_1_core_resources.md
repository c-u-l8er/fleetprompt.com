# FleetPrompt - Phase 1: Core Resources & Multi-Tenancy

## Overview
This phase implements the core Ash resources and multi-tenancy architecture that form the foundation of FleetPrompt.

## Prerequisites
- ✅ Phase 0 completed
- ✅ Phoenix server running
- ✅ Database configured
- ✅ Ash Framework installed

## Phase 1 Goals

1. ✅ Create Organization resource (tenant)
2. ✅ Create User resource with authentication
3. ✅ Implement schema-based multi-tenancy
4. ✅ Create Agent resource (core product)
5. ✅ Create Skill resource
6. ✅ Set up AshAdmin interface
7. ✅ Implement basic policies
8. ✅ Create seed data for development

## Core Resources Architecture

```
Organizations (public schema)
├── Users (public schema)
└── Tenant Data (org_<slug> schemas)
    ├── Agents
    ├── Skills
    ├── Workflows
    └── Executions
```

## Step-by-Step Implementation

### Step 1: Create Organization Resource

Create `lib/fleet_prompt/accounts/organization.ex`:

```elixir
defmodule FleetPrompt.Accounts.Organization do
  use Ash.Resource,
    domain: FleetPrompt.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "organizations"
    repo FleetPrompt.Repo
    
    # Automatic tenant schema creation
    manage_tenant do
      template ["org_", :slug]
      create? true
      update? false
    end
  end

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string do
      allow_nil? false
      public? true
    end
    
    attribute :slug, :string do
      allow_nil? false
      public? true
    end
    
    attribute :tier, :atom do
      constraints one_of: [:free, :pro, :enterprise]
      default :free
      public? true
    end
    
    attribute :billing_status, :atom do
      constraints one_of: [:active, :suspended, :trial, :canceled]
      default :trial
      public? true
    end
    
    # Usage limits based on tier
    attribute :monthly_token_limit, :integer do
      default 100_000
      public? true
    end
    
    attribute :agent_limit, :integer do
      default 3
      public? true
    end
    
    attribute :workflow_limit, :integer do
      default 0
      public? true
    end
    
    timestamps()
  end
  
  identities do
    identity :unique_slug, [:slug]
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:name, :slug, :tier]
      
      change fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :tier) || :free
        limits = calculate_tier_limits(tier)
        
        changeset
        |> Ash.Changeset.force_change_attribute(:monthly_token_limit, limits.tokens)
        |> Ash.Changeset.force_change_attribute(:agent_limit, limits.agents)
        |> Ash.Changeset.force_change_attribute(:workflow_limit, limits.workflows)
      end
    end
    
    update :update do
      accept [:name, :tier, :billing_status]
    end
    
    update :upgrade_tier do
      accept [:tier]
      
      change fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :tier)
        limits = calculate_tier_limits(tier)
        
        changeset
        |> Ash.Changeset.force_change_attribute(:monthly_token_limit, limits.tokens)
        |> Ash.Changeset.force_change_attribute(:agent_limit, limits.agents)
        |> Ash.Changeset.force_change_attribute(:workflow_limit, limits.workflows)
      end
    end
  end
  
  relationships do
    has_many :users, FleetPrompt.Accounts.User
  end
  
  # Ash Admin configuration
  admin do
    table_columns [:name, :slug, :tier, :billing_status]
  end
  
  # Helper function
  defp calculate_tier_limits(:free), do: %{tokens: 100_000, agents: 3, workflows: 0}
  defp calculate_tier_limits(:pro), do: %{tokens: 1_000_000, agents: 999, workflows: 10}
  defp calculate_tier_limits(:enterprise), do: %{tokens: 999_999_999, agents: 999, workflows: 999}

  # Required for Ash.ToTenant protocol
  defimpl Ash.ToTenant do
    def to_tenant(organization, _resource) do
      "org_#{organization.slug}"
    end
  end
end
```

### Step 2: Create User Resource

Create `lib/fleet_prompt/accounts/user.ex`:

```elixir
defmodule FleetPrompt.Accounts.User do
  use Ash.Resource,
    domain: FleetPrompt.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "users"
    repo FleetPrompt.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end
    
    attribute :hashed_password, :string do
      sensitive? true
      private? true
    end
    
    attribute :name, :string do
      public? true
    end
    
    attribute :role, :atom do
      constraints one_of: [:user, :admin, :developer]
      default :user
      public? true
    end
    
    attribute :confirmed_at, :utc_datetime_usec do
      public? true
    end
    
    timestamps()
  end
  
  identities do
    identity :unique_email, [:email]
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:email, :name, :organization_id]
      argument :password, :string, allow_nil? false, sensitive? true
      
      change fn changeset, _context ->
        password = Ash.Changeset.get_argument(changeset, :password)
        hashed = Bcrypt.hash_pwd_salt(password)
        
        Ash.Changeset.force_change_attribute(changeset, :hashed_password, hashed)
      end
    end
    
    update :update do
      accept [:email, :name, :role]
    end
    
    update :confirm do
      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :confirmed_at, DateTime.utc_now())
      end
    end
  end
  
  relationships do
    belongs_to :organization, FleetPrompt.Accounts.Organization do
      allow_nil? false
    end
  end
  
  admin do
    table_columns [:email, :name, :role, :confirmed_at]
  end
end
```

### Step 3: Create Agent Resource (Multi-tenant)

Create `lib/fleet_prompt/agents/agent.ex`:

```elixir
defmodule FleetPrompt.Agents.Agent do
  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshAdmin.Resource]

  postgres do
    table "agents"
    repo FleetPrompt.Repo
  end
  
  # Multi-tenancy via schema isolation
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
    
    attribute :version, :string do
      default "1.0.0"
      public? true
    end
    
    # Agent state machine
    attribute :status, :atom do
      constraints one_of: [:draft, :deploying, :active, :paused, :error]
      default :draft
      public? true
    end
    
    # Configuration (stored as JSON)
    attribute :config, :map do
      default %{
        model: "claude-sonnet-4",
        max_tokens: 4096,
        temperature: 0.7
      }
      public? true
    end
    
    # System prompt
    attribute :system_prompt, :string do
      allow_nil? false
      public? true
    end
    
    # Resource limits
    attribute :max_concurrent_requests, :integer do
      default 5
      public? true
    end
    
    attribute :timeout_seconds, :integer do
      default 30
      public? true
    end
    
    # Metrics
    attribute :total_executions, :integer do
      default 0
      public? true
    end
    
    attribute :total_tokens_used, :integer do
      default 0
      public? true
    end
    
    attribute :avg_latency_ms, :integer do
      public? true
    end
    
    timestamps()
  end
  
  # State machine transitions
  state_machine do
    initial_states [:draft]
    default_initial_state :draft
    
    transitions do
      transition :deploy, from: :draft, to: :deploying
      transition :activate, from: :deploying, to: :active
      transition :pause, from: :active, to: :paused
      transition :resume, from: :paused, to: :active
      transition :error, from: [:deploying, :active], to: :error
      transition :redeploy, from: :error, to: :deploying
    end
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:name, :description, :system_prompt, :config]
    end
    
    update :update do
      accept [:name, :description, :system_prompt, :config, 
              :max_concurrent_requests, :timeout_seconds]
    end
    
    # State machine actions
    update :deploy, do: change transition_state(:deploying)
    update :activate, do: change transition_state(:active)
    update :pause, do: change transition_state(:paused)
    update :resume, do: change transition_state(:active)
  end
  
  # Policies for authorization
  policies do
    policy action_type(:read) do
      authorize_if always()
    end
    
    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end
  end
  
  admin do
    table_columns [:name, :status, :version, :total_executions]
  end
end
```

### Step 4: Create Skill Resource

Create `lib/fleet_prompt/skills/skill.ex`:

```elixir
defmodule FleetPrompt.Skills.Skill do
  use Ash.Resource,
    domain: FleetPrompt.Skills,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "skills"
    repo FleetPrompt.Repo
  end
  
  # Skills are global (not multi-tenant)
  
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string do
      allow_nil? false
      public? true
    end
    
    attribute :slug, :string do
      allow_nil? false
      public? true
    end
    
    attribute :description, :string do
      public? true
    end
    
    attribute :category, :atom do
      constraints one_of: [:research, :coding, :data_analysis, :communication, :operations]
      public? true
    end
    
    attribute :tier_required, :atom do
      constraints one_of: [:free, :pro, :enterprise]
      default :free
      public? true
    end
    
    attribute :system_prompt_enhancement, :string do
      allow_nil? false
      public? true
    end
    
    attribute :tools, {:array, :string} do
      default []
      public? true
    end
    
    attribute :is_official, :boolean do
      default false
      public? true
    end
    
    timestamps()
  end
  
  identities do
    identity :unique_slug, [:slug]
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
  end
  
  admin do
    table_columns [:name, :category, :tier_required, :is_official]
  end
end
```

### Step 5: Update Domain Modules

Update `lib/fleet_prompt/accounts.ex`:

```elixir
defmodule FleetPrompt.Accounts do
  use Ash.Domain

  resources do
    resource FleetPrompt.Accounts.Organization
    resource FleetPrompt.Accounts.User
  end
end
```

Update `lib/fleet_prompt/agents.ex`:

```elixir
defmodule FleetPrompt.Agents do
  use Ash.Domain

  resources do
    resource FleetPrompt.Agents.Agent
  end
end
```

Update `lib/fleet_prompt/skills.ex`:

```elixir
defmodule FleetPrompt.Skills do
  use Ash.Domain

  resources do
    resource FleetPrompt.Skills.Skill
  end
end
```

### Step 6: Generate Migrations

```bash
# Generate migration for all resources
mix ash_postgres.generate_migrations --name add_core_resources

# Review the generated migration in priv/repo/migrations/

# Run migration
mix ecto.migrate
```

### Step 7: Update Repo for Multi-tenancy

Update `lib/fleet_prompt/repo.ex`:

```elixir
defmodule FleetPrompt.Repo do
  use AshPostgres.Repo,
    otp_app: :fleet_prompt

  def installed_extensions do
    ["uuid-ossp", "citext"]
  end

  # Required for multi-tenancy
  def all_tenants do
    import Ecto.Query
    
    from(o in "organizations", select: fragment("'org_' || ?", o.slug))
    |> __MODULE__.all()
  end
  
  def min_pg_version do
    # Minimum PostgreSQL version required
    %Version{major: 14, minor: 0, patch: 0}
  end
end
```

### Step 8: Set Up AshAdmin

Update `lib/fleet_prompt_web/router.ex`:

```elixir
defmodule FleetPromptWeb.Router do
  use FleetPromptWeb, :router
  import AshAdmin.Router

  # ... existing pipelines ...

  pipeline :admin do
    # Add authentication here in future
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {FleetPromptWeb.Layouts, :root}
  end

  scope "/" do
    pipe_through [:browser, :admin]
    
    ash_admin "/admin",
      domains: [
        FleetPrompt.Accounts,
        FleetPrompt.Agents,
        FleetPrompt.Skills
      ]
  end

  # ... rest of routes ...
end
```

### Step 9: Create Seed Data

Create `priv/repo/seeds.exs`:

```elixir
# Create demo organization
{:ok, org} = FleetPrompt.Accounts.Organization
  |> Ash.Changeset.for_create(:create, %{
    name: "Demo Company",
    slug: "demo",
    tier: :pro
  })
  |> Ash.create()

IO.puts("Created organization: #{org.name} (org_#{org.slug})")

# Create admin user
{:ok, admin} = FleetPrompt.Accounts.User
  |> Ash.Changeset.for_create(:create, %{
    email: "admin@demo.com",
    name: "Admin User",
    password: "password123",
    organization_id: org.id,
    role: :admin
  })
  |> Ash.create()

IO.puts("Created admin user: #{admin.email}")

# Create some demo skills
skills_data = [
  %{
    name: "Web Research",
    slug: "web-research",
    description: "Advanced web search and information gathering",
    category: :research,
    tier_required: :free,
    system_prompt_enhancement: """
    You have access to web search capabilities. When researching:
    1. Search for authoritative sources
    2. Cross-reference multiple sources
    3. Evaluate source credibility
    4. Cite all sources in your response
    """,
    tools: ["web_search", "web_fetch"],
    is_official: true
  },
  %{
    name: "Code Analysis",
    slug: "code-analysis",
    description: "Analyze and review code for best practices",
    category: :coding,
    tier_required: :pro,
    system_prompt_enhancement: """
    You are an expert code reviewer. When analyzing code:
    1. Check for security vulnerabilities
    2. Assess code quality and maintainability
    3. Suggest improvements and optimizations
    4. Follow language-specific best practices
    """,
    tools: ["ast_parse", "static_analysis"],
    is_official: true
  },
  %{
    name: "Customer Communication",
    slug: "customer-communication",
    description: "Professional customer service and support",
    category: :communication,
    tier_required: :free,
    system_prompt_enhancement: """
    You are a professional customer service representative. 
    - Be empathetic and understanding
    - Provide clear, actionable solutions
    - Maintain a friendly, professional tone
    - Ask clarifying questions when needed
    """,
    tools: ["send_email", "send_sms"],
    is_official: true
  }
]

for skill_data <- skills_data do
  {:ok, skill} = FleetPrompt.Skills.Skill
    |> Ash.Changeset.for_create(:create, skill_data)
    |> Ash.create()
  
  IO.puts("Created skill: #{skill.name}")
end

# Create demo agent in org context
{:ok, agent} = FleetPrompt.Agents.Agent
  |> Ash.Changeset.for_create(:create, %{
    name: "Research Assistant",
    description: "AI research assistant with web search capabilities",
    system_prompt: """
    You are a research assistant. Your job is to:
    1. Understand the user's research question
    2. Search for relevant information
    3. Synthesize findings into clear summaries
    4. Cite all sources
    
    Be thorough, accurate, and objective.
    """,
    config: %{
      model: "claude-sonnet-4",
      max_tokens: 4096,
      temperature: 0.7
    }
  })
  |> Ash.Changeset.set_tenant(org)
  |> Ash.create()

IO.puts("Created demo agent: #{agent.name}")

IO.puts("\n✅ Seed data created successfully!")
IO.puts("\nLogin credentials:")
IO.puts("  Email: admin@demo.com")
IO.puts("  Password: password123")
IO.puts("\nAdmin panel: http://localhost:4000/admin")
```

Run seeds:

```bash
mix run priv/repo/seeds.exs
```

### Step 10: Test Multi-tenancy

Create `test/fleet_prompt/agents/agent_test.exs`:

```elixir
defmodule FleetPrompt.Agents.AgentTest do
  use FleetPrompt.DataCase

  alias FleetPrompt.Accounts.Organization
  alias FleetPrompt.Agents.Agent

  setup do
    # Create test organization
    {:ok, org} = Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Org",
        slug: "test-org",
        tier: :pro
      })
      |> Ash.create()
    
    %{org: org}
  end

  test "creates agent in tenant context", %{org: org} do
    {:ok, agent} = Agent
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Agent",
        description: "A test agent",
        system_prompt: "You are helpful."
      })
      |> Ash.Changeset.set_tenant(org)
      |> Ash.create()
    
    assert agent.name == "Test Agent"
    assert agent.status == :draft
  end

  test "agent state transitions", %{org: org} do
    {:ok, agent} = Agent
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Agent",
        system_prompt: "You are helpful."
      })
      |> Ash.Changeset.set_tenant(org)
      |> Ash.create()
    
    # Deploy agent
    {:ok, agent} = agent
      |> Ash.Changeset.for_update(:deploy)
      |> Ash.update()
    
    assert agent.status == :deploying
  end
end
```

Run tests:

```bash
mix test
```

## Verification Checklist

- [ ] Organizations table created
- [ ] Users table created
- [ ] Agents table created in tenant schemas
- [ ] Skills table created
- [ ] Migrations run successfully
- [ ] Seed data loads
- [ ] Admin panel accessible at `/admin`
- [ ] Can create organizations
- [ ] Can create users
- [ ] Can create agents in tenant context
- [ ] Tests pass

## Expected Database Schema

### Public Schema
- `organizations` - Tenant definitions
- `users` - User accounts
- `skills` - Global skills catalog

### Tenant Schemas (org_<slug>)
- `agents` - Tenant-specific agents
- (More tables in future phases)

## Common Issues & Solutions

### Issue: Migration fails with tenant schema
**Solution:** Ensure `all_tenants/0` returns empty list initially:
```elixir
def all_tenants, do: []
```

### Issue: Can't access admin panel
**Solution:** Check router pipeline configuration and restart server.

### Issue: Tenant not found error
**Solution:** Always use `Ash.Changeset.set_tenant(org)` for multi-tenant resources.

## Next Phase

**Phase 2: Package System & Marketplace**
- Create Package resource
- Create Installation resource
- Build package installer
- Create marketplace UI
- Implement package registry

## Resources

- [Ash Multi-tenancy Guide](https://hexdocs.pm/ash/multitenancy.html)
- [AshStateMachine Docs](https://hexdocs.pm/ash_state_machine)
- [AshAdmin Guide](https://hexdocs.pm/ash_admin)

---

**Completion Status:** Phase 1 establishes core resources and multi-tenancy. Move to Phase 2 when all verification items are checked.
