# FleetPrompt - Phase 2: Package System & Marketplace

## Overview
This phase implements the **Package System** as a first-class platform primitive (not just a marketplace UI): packages are versioned, composable units that can install **skills**, **agents**, and **workflows**, and communicate via a standardized **signal/event architecture**.

**Canonical Phase 2B spec:** persisted, replayable Signals + auditable Directives are specified in:
- `fleetprompt.com/project_plan/phase_2b_signals_and_directives.md`

The marketplace UX (browse/search/install/reviews) is still delivered here, but Phase 2 is re-scoped to ensure the underlying primitives exist so that packages are:
- **Composable** (skills + signals, not just “a bundle of code”)
- **Upgradeable** (versioning + schema evolution)
- **Operable** (install lifecycle + telemetry hooks)
- **Multi-tenant safe** (global registry; tenant-scoped installations and runtime state)

## Prerequisites
- ✅ Phase 0 completed (Inertia + Svelte setup)
- ✅ Phase 1 completed (Core resources)

## Phase 2 Goals

### A) Platform primitives (must-have to make packages “real”)
1. ✅ **Package Registry (global)**: `Package` resource with versioning metadata and compatibility fields (platform + schema).
2. ✅ **Package Installation (tenant-scoped)**: `Installation` resource that tracks install status, installed version, and runtime configuration per org/tenant.
3. ✅ **Signals (event system) baseline**: define the minimal signal envelope and a publish/subscribe contract that packages can rely on (**persisted + replayable Signals + auditable Directives are specified in** `fleetprompt.com/project_plan/phase_2b_signals_and_directives.md`).
4. ✅ **Skills as the unit of composition**: packages install skills (and optionally agents/workflows) rather than only “agents”, enabling reuse across verticals.
5. ✅ **Versioning + schema evolution hooks**: establish package version semantics and a migration/compatibility strategy for installed packages.

### B) Delivery mechanics (how installs happen)
6. ✅ **Installer job**: background job that applies package install steps deterministically (idempotent, retry-safe).
7. ✅ **Install lifecycle**: install/upgrade/uninstall states and audit trail (who installed, when, what changed).

### C) Marketplace experience (how customers discover and trust packages)
8. ✅ Marketplace UI (browse/search/filter)
9. ✅ Package detail pages
10. ✅ Installation flow (with clear “what will be installed” preview)
11. ✅ Reviews & ratings

## Backend Implementation

### Step 1: Create Package Resource

Create `lib/fleet_prompt/packages/package.ex`:

```elixir
defmodule FleetPrompt.Packages.Package do
  use Ash.Resource,
    domain: FleetPrompt.Packages,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "packages"
    repo FleetPrompt.Repo
  end

  # Packages are global (not multi-tenant): this is the canonical registry/metadata.
  # Tenant-specific adoption happens via `Installation` in the tenant context.
  #
  # IMPORTANT (Phase 2 realignment):
  # - Packages must be versioned and upgradeable (schema evolution + compatibility)
  # - Packages should install composable primitives (skills/signals/workflows/agents)
  # - Runtime communication between installed components should use the signal/event system
  
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
    
    attribute :version, :string do
      allow_nil? false
      public? true
    end
    
    attribute :description, :string do
      public? true
    end
    
    attribute :long_description, :string do
      public? true
    end
    
    attribute :category, :atom do
      constraints one_of: [
        :operations,
        :customer_service,
        :sales,
        :data,
        :development,
        :marketing,
        :finance,
        :hr
      ]
      public? true
    end
    
    # Package metadata
    attribute :author, :string do
      public? true
    end
    
    attribute :author_url, :string do
      public? true
    end
    
    attribute :repository_url, :string do
      public? true
    end
    
    attribute :documentation_url, :string do
      public? true
    end
    
    attribute :license, :string do
      default "MIT"
      public? true
    end
    
    # Package icon/logo
    attribute :icon_url, :string do
      public? true
    end
    
    # Pricing
    attribute :pricing_model, :atom do
      constraints one_of: [:free, :freemium, :paid, :revenue_share]
      default :free
      public? true
    end
    
    attribute :pricing_config, :map do
      default %{}
      public? true
    end
    
    # Requirements
    attribute :min_fleet_prompt_tier, :atom do
      constraints one_of: [:free, :pro, :enterprise]
      default :free
      public? true
    end
    
    attribute :dependencies, {:array, :map} do
      default []
      public? true
    end
    
    # Package content
    attribute :package_url, :string do
      public? true
    end
    
    attribute :checksum, :string do
      public? true
    end
    
    # Package includes (for display)
    attribute :includes, :map do
      default %{
        agents: [],
        workflows: [],
        skills: [],
        tools: []
      }
      public? true
    end
    
    # Stats
    attribute :install_count, :integer do
      default 0
      public? true
    end
    
    attribute :active_install_count, :integer do
      default 0
      public? true
    end
    
    attribute :rating_avg, :decimal do
      public? true
    end
    
    attribute :rating_count, :integer do
      default 0
      public? true
    end
    
    # Flags
    attribute :is_verified, :boolean do
      default false
      public? true
    end
    
    attribute :is_featured, :boolean do
      default false
      public? true
    end
    
    attribute :is_published, :boolean do
      default false
      public? true
    end
    
    timestamps()
  end
  
  identities do
    identity :unique_name_version, [:name, :version]
    identity :unique_slug, [:slug]
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [
        :name, :slug, :version, :description, :long_description,
        :category, :author, :author_url, :repository_url,
        :documentation_url, :license, :icon_url,
        :pricing_model, :pricing_config, :min_fleet_prompt_tier,
        :dependencies, :package_url, :checksum, :includes
      ]
    end
    
    update :update do
      accept [
        :description, :long_description, :icon_url,
        :pricing_config, :documentation_url, :is_published
      ]
    end
    
    update :increment_installs do
      change fn changeset, _context ->
        current = changeset.data.install_count
        Ash.Changeset.force_change_attribute(changeset, :install_count, current + 1)
      end
    end
    
    read :search do
      argument :query, :string
      argument :category, :atom
      argument :pricing_model, :atom
      argument :tier, :atom
      
      prepare fn query, context ->
        query
        |> filter_by_search(context[:query])
        |> filter_by_category(context[:category])
        |> filter_by_pricing(context[:pricing_model])
        |> filter_by_tier(context[:tier])
        |> Ash.Query.filter(is_published == true)
        |> Ash.Query.sort(install_count: :desc)
      end
    end
    
    read :featured do
      filter expr(is_featured == true and is_published == true)
      limit 6
    end
    
    read :by_slug do
      argument :slug, :string, allow_nil? false
      get? true
      filter expr(slug == ^arg(:slug))
    end
  end
  
  relationships do
    has_many :installations, FleetPrompt.Packages.Installation
    has_many :reviews, FleetPrompt.Packages.Review
  end
  
  calculations do
    calculate :can_install, :boolean, expr(is_published == true)
  end
  
  # Helper functions for filtering
  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, search_term) do
    Ash.Query.filter(query, 
      contains(name, ^search_term) or contains(description, ^search_term)
    )
  end
  
  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, category) do
    Ash.Query.filter(query, category == ^category)
  end
  
  defp filter_by_pricing(query, nil), do: query
  defp filter_by_pricing(query, pricing) do
    Ash.Query.filter(query, pricing_model == ^pricing)
  end
  
  defp filter_by_tier(query, nil), do: query
  defp filter_by_tier(query, tier) do
    available_tiers = case tier do
      :free -> [:free]
      :pro -> [:free, :pro]
      :enterprise -> [:free, :pro, :enterprise]
    end
    Ash.Query.filter(query, min_fleet_prompt_tier in ^available_tiers)
  end
end
```

### Step 2: Create Installation Resource

Create `lib/fleet_prompt/packages/installation.ex`:

```elixir
defmodule FleetPrompt.Packages.Installation do
  use Ash.Resource,
    domain: FleetPrompt.Packages,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "package_installations"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :package_slug, :string do
      allow_nil? false
      public? true
    end
    
    attribute :package_version, :string do
      allow_nil? false
      public? true
    end
    
    attribute :status, :atom do
      constraints one_of: [:queued, :installing, :active, :paused, :failed, :uninstalling]
      default :queued
      public? true
    end
    
    attribute :config, :map do
      default %{}
      public? true
    end
    
    attribute :installed_resources, :map do
      default %{
        agents: [],
        workflows: [],
        skills: []
      }
      public? true
    end
    
    attribute :error_message, :string do
      public? true
    end
    
    attribute :installed_at, :utc_datetime_usec do
      public? true
    end
    
    timestamps()
  end
  
  state_machine do
    initial_states [:queued]
    default_initial_state :queued
    
    transitions do
      transition :start_install, from: :queued, to: :installing
      transition :complete_install, from: :installing, to: :active
      transition :fail_install, from: :installing, to: :failed
      transition :pause, from: :active, to: :paused
      transition :resume, from: :paused, to: :active
      transition :start_uninstall, from: [:active, :paused, :failed], to: :uninstalling
    end
  end
  
  actions do
    defaults [:read]
    
    create :install do
      argument :package_id, :uuid, allow_nil: false
      
      change fn changeset, context ->
        package_id = Ash.Changeset.get_argument(changeset, :package_id)
        package = FleetPrompt.Packages.Package
                  |> Ash.get!(package_id)
        
        org = context.tenant
        
        # Verify tier access
        unless can_install_package?(org, package) do
          raise "Package requires #{package.min_fleet_prompt_tier} tier"
        end
        
        changeset
        |> Ash.Changeset.force_change_attribute(:package_slug, package.slug)
        |> Ash.Changeset.force_change_attribute(:package_version, package.version)
      end
      
      after_action fn _changeset, installation, context ->
        # Queue background job
        {:ok, _job} = FleetPrompt.Jobs.PackageInstaller.enqueue(%{
          installation_id: installation.id,
          tenant: context.tenant
        })
        
        {:ok, installation}
      end
    end
    
    update :configure do
      accept [:config]
    end
    
    update :complete do
      argument :installed_resources, :map, allow_nil? false
      
      change fn changeset, _context ->
        resources = Ash.Changeset.get_argument(changeset, :installed_resources)
        
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :active)
        |> Ash.Changeset.force_change_attribute(:installed_resources, resources)
        |> Ash.Changeset.force_change_attribute(:installed_at, DateTime.utc_now())
      end
    end
    
    destroy :uninstall do
      change fn changeset, context ->
        # Queue uninstall job
        {:ok, _job} = FleetPrompt.Jobs.PackageUninstaller.enqueue(%{
          installation_id: changeset.data.id,
          tenant: context.tenant
        })
        
        changeset
      end
    end
  end
  
  relationships do
    belongs_to :organization, FleetPrompt.Accounts.Organization
    belongs_to :package, FleetPrompt.Packages.Package do
      source_attribute :package_id
    end
  end
  
  defp can_install_package?(org, package) do
    tier_hierarchy = %{free: 0, pro: 1, enterprise: 2}
    tier_hierarchy[org.tier] >= tier_hierarchy[package.min_fleet_prompt_tier]
  end
end
```

### Step 3: Create Package Review Resource

Create `lib/fleet_prompt/packages/review.ex`:

```elixir
defmodule FleetPrompt.Packages.Review do
  use Ash.Resource,
    domain: FleetPrompt.Packages,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "package_reviews"
    repo FleetPrompt.Repo
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :rating, :integer do
      constraints min: 1, max: 5
      allow_nil? false
      public? true
    end
    
    attribute :title, :string do
      public? true
    end
    
    attribute :content, :string do
      public? true
    end
    
    attribute :helpful_count, :integer do
      default 0
      public? true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
  end
  
  relationships do
    belongs_to :package, FleetPrompt.Packages.Package
    belongs_to :user, FleetPrompt.Accounts.User
  end
end
```

### Step 4: Update Packages Domain

Update `lib/fleet_prompt/packages.ex`:

```elixir
defmodule FleetPrompt.Packages do
  use Ash.Domain

  resources do
    resource FleetPrompt.Packages.Package
    resource FleetPrompt.Packages.Installation
    resource FleetPrompt.Packages.Review
  end
end
```

### Step 5: Create Package Installer Job

Create `lib/fleet_prompt/jobs/package_installer.ex`:

```elixir
defmodule FleetPrompt.Jobs.PackageInstaller do
  use Oban.Worker, queue: :package_installation, max_attempts: 3
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"installation_id" => installation_id, "tenant" => tenant}}) do
    installation = load_installation(installation_id, tenant)
    package = load_package(installation.package_slug, installation.package_version)
    
    with {:ok, agents} <- install_agents(package, tenant),
         {:ok, workflows} <- install_workflows(package, tenant),
         {:ok, skills} <- install_skills(package, tenant) do
      
      # Mark as complete
      installation
      |> Ash.Changeset.for_update(:complete, %{
        installed_resources: %{
          agents: Enum.map(agents, & &1.id),
          workflows: Enum.map(workflows, & &1.id),
          skills: Enum.map(skills, & &1.id)
        }
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.update!()
      
      # Increment package install count
      package
      |> Ash.Changeset.for_update(:increment_installs)
      |> Ash.update!()
      
      :ok
    else
      {:error, reason} ->
        # Mark as failed
        installation
        |> Ash.Changeset.for_update(:fail, %{error_message: inspect(reason)})
        |> Ash.Changeset.set_tenant(tenant)
        |> Ash.update!()
        
        {:error, reason}
    end
  end
  
  defp load_installation(id, tenant) do
    FleetPrompt.Packages.Installation
    |> Ash.get!(id, tenant: tenant)
  end
  
  defp load_package(slug, version) do
    FleetPrompt.Packages.Package
    |> Ash.Query.filter(slug == ^slug and version == ^version)
    |> Ash.read_one!()
  end
  
  defp install_agents(package, tenant) do
    agents = for agent_config <- package.includes["agents"] || [] do
      FleetPrompt.Agents.Agent
      |> Ash.Changeset.for_create(:create, %{
        name: agent_config["name"],
        description: agent_config["description"],
        system_prompt: agent_config["system_prompt"],
        config: agent_config["config"] || %{}
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create!()
    end
    
    {:ok, agents}
  end
  
  defp install_workflows(package, tenant) do
    # Similar to agents
    {:ok, []}
  end
  
  defp install_skills(package, tenant) do
    # Skills are global, just return references
    {:ok, []}
  end
end
```

### Step 6: Generate Migrations

```bash
mix ash_postgres.generate_migrations --name add_packages_system
mix ecto.migrate
```

### Step 7: Create Seed Data

Add to `priv/repo/seeds.exs`:

```elixir
# Create packages
packages_data = [
  %{
    name: "Field Service Management",
    slug: "field-service",
    version: "1.0.0",
    description: "Complete field service system with dispatcher, customer service, QA, and inventory agents",
    long_description: """
    The Field Service Management package includes everything you need to run a professional field service operation:
    
    - **Dispatcher Agent**: Intelligent scheduling and technician assignment
    - **Customer Service Agent**: Automated customer communication
    - **QA Inspector Agent**: Quality assurance and compliance checking
    - **Inventory Manager Agent**: Parts tracking and automated ordering
    
    Perfect for HVAC, plumbing, electrical, and other field service businesses.
    """,
    category: :operations,
    author: "FleetPrompt Team",
    license: "MIT",
    icon_url: "/images/packages/field-service.svg",
    pricing_model: :freemium,
    pricing_config: %{
      tiers: [
        %{name: "Free", limit: 100, price: 0},
        %{name: "Pro", limit: 5000, price: 99}
      ]
    },
    min_fleet_prompt_tier: :pro,
    dependencies: [],
    includes: %{
      agents: [
        %{name: "Dispatcher", description: "Intelligent scheduling"},
        %{name: "Customer Service", description: "Automated communication"},
        %{name: "QA Inspector", description: "Quality assurance"},
        %{name: "Inventory Manager", description: "Parts management"}
      ],
      workflows: [
        %{name: "Service Request", description: "End-to-end service workflow"}
      ]
    },
    install_count: 2547,
    rating_avg: Decimal.new("4.8"),
    rating_count: 234,
    is_verified: true,
    is_featured: true,
    is_published: true
  },
  %{
    name: "Customer Support Hub",
    slug: "customer-support",
    version: "2.1.0",
    description: "AI-powered ticket management, live chat, email responses, and knowledge base",
    long_description: """
    Transform your customer support with AI agents that handle tickets, chat, and email automatically.
    """,
    category: :customer_service,
    author: "FleetPrompt Team",
    license: "MIT",
    icon_url: "/images/packages/customer-support.svg",
    pricing_model: :paid,
    pricing_config: %{price: 149},
    min_fleet_prompt_tier: :free,
    includes: %{
      agents: [
        %{name: "Ticket Manager", description: "Automatic ticket triage"},
        %{name: "Live Chat", description: "Real-time chat support"},
        %{name: "Email Responder", description: "Intelligent email handling"}
      ]
    },
    install_count: 3201,
    rating_avg: Decimal.new("4.9"),
    rating_count: 412,
    is_verified: true,
    is_featured: true,
    is_published: true
  },
  %{
    name: "Sales Automation",
    slug: "sales-automation",
    version: "1.5.0",
    description: "Lead qualification, outreach sequences, meeting scheduling, and proposal generation",
    category: :sales,
    author: "SalesAI Inc",
    license: "Proprietary",
    icon_url: "/images/packages/sales-automation.svg",
    pricing_model: :revenue_share,
    pricing_config: %{percentage: 15},
    min_fleet_prompt_tier: :pro,
    includes: %{
      agents: [
        %{name: "Lead Qualifier", description: "Intelligent lead scoring"},
        %{name: "Outreach Agent", description: "Automated email sequences"}
      ]
    },
    install_count: 1876,
    rating_avg: Decimal.new("4.6"),
    rating_count: 189,
    is_verified: false,
    is_featured: false,
    is_published: true
  }
]

for package_data <- packages_data do
  {:ok, _package} = FleetPrompt.Packages.Package
    |> Ash.Changeset.for_create(:create, package_data)
    |> Ash.create()
  
  IO.puts("Created package: #{package_data.name}")
end
```

## Frontend Implementation (Svelte + shadcn)

### Step 8: Create Marketplace Controller

Create `lib/fleet_prompt_web/controllers/marketplace_controller.ex`:

```elixir
defmodule FleetPromptWeb.MarketplaceController do
  use FleetPromptWeb, :controller
  
  def index(conn, params) do
    packages = FleetPrompt.Packages.Package
               |> Ash.Query.for_read(:search, %{
                 query: params["q"],
                 category: params["category"],
                 pricing_model: params["pricing"]
               })
               |> Ash.read!()
    
    featured = FleetPrompt.Packages.Package
               |> Ash.Query.for_read(:featured)
               |> Ash.read!()
    
    render_inertia(conn, "Marketplace/Index",
      props: %{
        packages: serialize_packages(packages),
        featured: serialize_packages(featured),
        filters: %{
          query: params["q"],
          category: params["category"],
          pricing: params["pricing"]
        }
      }
    )
  end
  
  def show(conn, %{"slug" => slug}) do
    package = FleetPrompt.Packages.Package
              |> Ash.Query.for_read(:by_slug, %{slug: slug})
              |> Ash.read_one!()
    
    reviews = FleetPrompt.Packages.Review
              |> Ash.Query.filter(package_id == ^package.id)
              |> Ash.Query.sort(inserted_at: :desc)
              |> Ash.Query.limit(10)
              |> Ash.read!()
    
    # Check if current user has installed this
    current_org = conn.assigns[:current_org]
    installation = if current_org do
      FleetPrompt.Packages.Installation
      |> Ash.Query.filter(package_slug == ^slug and status == :active)
      |> Ash.Query.set_tenant(current_org)
      |> Ash.read_one()
    else
      nil
    end
    
    render_inertia(conn, "Marketplace/Show",
      props: %{
        package: serialize_package_detail(package),
        reviews: serialize_reviews(reviews),
        is_installed: !is_nil(installation)
      }
    )
  end
  
  defp serialize_packages(packages) do
    Enum.map(packages, fn pkg ->
      %{
        id: pkg.id,
        name: pkg.name,
        slug: pkg.slug,
        description: pkg.description,
        category: pkg.category,
        icon_url: pkg.icon_url,
        pricing_model: pkg.pricing_model,
        pricing_config: pkg.pricing_config,
        install_count: pkg.install_count,
        rating_avg: pkg.rating_avg,
        rating_count: pkg.rating_count,
        is_verified: pkg.is_verified,
        is_featured: pkg.is_featured
      }
    end)
  end
  
  defp serialize_package_detail(pkg) do
    Map.merge(serialize_packages([pkg]) |> List.first(), %{
      long_description: pkg.long_description,
      author: pkg.author,
      author_url: pkg.author_url,
      repository_url: pkg.repository_url,
      documentation_url: pkg.documentation_url,
      license: pkg.license,
      version: pkg.version,
      includes: pkg.includes,
      dependencies: pkg.dependencies,
      min_fleet_prompt_tier: pkg.min_fleet_prompt_tier
    })
  end
  
  defp serialize_reviews(reviews) do
    Enum.map(reviews, fn review ->
      %{
        id: review.id,
        rating: review.rating,
        title: review.title,
        content: review.content,
        helpful_count: review.helpful_count,
        inserted_at: review.inserted_at
      }
    end)
  end
end
```

### Step 9: Add Routes

Update `lib/fleet_prompt_web/router.ex`:

```elixir
scope "/", FleetPromptWeb do
  pipe_through :browser

  get "/", PageController, :home
  get "/marketplace", MarketplaceController, :index
  get "/marketplace/:slug", MarketplaceController, :show
end
```

### Step 10: Create shadcn-svelte Components

Create Button component `assets/src/lib/components/ui/button/Button.svelte`:

```svelte
<script lang="ts">
  import { cn } from "$lib/utils/cn";
  import type { Snippet } from "svelte";
  
  interface Props {
    variant?: "default" | "destructive" | "outline" | "secondary" | "ghost" | "link";
    size?: "default" | "sm" | "lg" | "icon";
    class?: string;
    children: Snippet;
    [key: string]: any;
  }
  
  let { 
    variant = "default", 
    size = "default",
    class: className,
    children,
    ...rest
  }: Props = $props();
  
  const variants = {
    default: "bg-primary text-primary-foreground hover:bg-primary/90",
    destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
    outline: "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
    secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
    ghost: "hover:bg-accent hover:text-accent-foreground",
    link: "text-primary underline-offset-4 hover:underline",
  };
  
  const sizes = {
    default: "h-10 px-4 py-2",
    sm: "h-9 rounded-md px-3",
    lg: "h-11 rounded-md px-8",
    icon: "h-10 w-10",
  };
</script>

<button
  class={cn(
    "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
    variants[variant],
    sizes[size],
    className
  )}
  {...rest}
>
  {@render children()}
</button>
```

Create Card components `assets/src/lib/components/ui/card/Card.svelte`:

```svelte
<script lang="ts">
  import { cn } from "$lib/utils/cn";
  import type { Snippet } from "svelte";
  
  interface Props {
    class?: string;
    children: Snippet;
  }
  
  let { class: className, children }: Props = $props();
</script>

<div class={cn("rounded-lg border bg-card text-card-foreground shadow-sm", className)}>
  {@render children()}
</div>
```

Create `assets/src/lib/components/ui/card/CardHeader.svelte`:

```svelte
<script lang="ts">
  import { cn } from "$lib/utils/cn";
  import type { Snippet } from "svelte";
  
  interface Props {
    class?: string;
    children: Snippet;
  }
  
  let { class: className, children }: Props = $props();
</script>

<div class={cn("flex flex-col space-y-1.5 p-6", className)}>
  {@render children()}
</div>
```

Create `assets/src/lib/components/ui/card/CardTitle.svelte`:

```svelte
<script lang="ts">
  import { cn } from "$lib/utils/cn";
  import type { Snippet } from "svelte";
  
  interface Props {
    class?: string;
    children: Snippet;
  }
  
  let { class: className, children }: Props = $props();
</script>

<h3 class={cn("text-2xl font-semibold leading-none tracking-tight", className)}>
  {@render children()}
</h3>
```

Create `assets/src/lib/components/ui/card/CardContent.svelte`:

```svelte
<script lang="ts">
  import { cn } from "$lib/utils/cn";
  import type { Snippet } from "svelte";
  
  interface Props {
    class?: string;
    children: Snippet;
  }
  
  let { class: className, children }: Props = $props();
</script>

<div class={cn("p-6 pt-0", className)}>
  {@render children()}
</div>
```

### Step 11: Create Marketplace Index Page

Create `assets/src/pages/Marketplace/Index.svelte`:

```svelte
<script lang="ts">
  import { inertia, router } from '@inertiajs/svelte';
  import Button from '$lib/components/ui/button/Button.svelte';
  import Card from '$lib/components/ui/card/Card.svelte';
  import CardHeader from '$lib/components/ui/card/CardHeader.svelte';
  import CardTitle from '$lib/components/ui/card/CardTitle.svelte';
  import CardContent from '$lib/components/ui/card/CardContent.svelte';
  import { Star, Download, Verified } from 'lucide-svelte';
  
  interface Package {
    id: string;
    name: string;
    slug: string;
    description: string;
    category: string;
    icon_url: string;
    pricing_model: string;
    pricing_config: any;
    install_count: number;
    rating_avg: number;
    rating_count: number;
    is_verified: boolean;
    is_featured: boolean;
  }
  
  interface Props {
    packages: Package[];
    featured: Package[];
    filters: {
      query?: string;
      category?: string;
      pricing?: string;
    };
  }
  
  let { packages, featured, filters }: Props = $props();
  
  let searchQuery = $state(filters.query || '');
  let selectedCategory = $state(filters.category || '');
  let selectedPricing = $state(filters.pricing || '');
  
  const categories = [
    { value: '', label: 'All Categories' },
    { value: 'operations', label: 'Operations' },
    { value: 'customer_service', label: 'Customer Service' },
    { value: 'sales', label: 'Sales' },
    { value: 'data', label: 'Data & Analytics' },
    { value: 'development', label: 'Development' },
    { value: 'marketing', label: 'Marketing' },
    { value: 'finance', label: 'Finance' },
    { value: 'hr', label: 'Human Resources' },
  ];
  
  const pricingModels = [
    { value: '', label: 'All Pricing' },
    { value: 'free', label: 'Free' },
    { value: 'freemium', label: 'Freemium' },
    { value: 'paid', label: 'Paid' },
    { value: 'revenue_share', label: 'Revenue Share' },
  ];
  
  function handleSearch() {
    router.get('/marketplace', {
      q: searchQuery,
      category: selectedCategory,
      pricing: selectedPricing
    }, {
      preserveState: true,
      preserveScroll: true
    });
  }
  
  function formatInstalls(count: number): string {
    if (count >= 1000) {
      return `${(count / 1000).toFixed(1)}K`;
    }
    return count.toString();
  }
  
  function formatPrice(pkg: Package): string {
    switch (pkg.pricing_model) {
      case 'free':
        return 'Free';
      case 'freemium':
        return 'Free tier available';
      case 'paid':
        return `$${pkg.pricing_config.price}/mo`;
      case 'revenue_share':
        return `${pkg.pricing_config.percentage}% revenue share`;
      default:
        return 'Custom pricing';
    }
  }
</script>

<div class="min-h-screen bg-background">
  <!-- Hero Section -->
  <div class="bg-gradient-to-r from-primary/10 via-primary/5 to-background border-b">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
      <h1 class="text-4xl font-bold tracking-tight mb-4">
        Package Marketplace
      </h1>
      <p class="text-xl text-muted-foreground max-w-2xl">
        Pre-built agent systems ready to deploy. Browse, install, and start automating in minutes.
      </p>
    </div>
  </div>
  
  <!-- Filters -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex gap-4 flex-wrap">
      <input
        type="text"
        bind:value={searchQuery}
        onkeydown={(e) => e.key === 'Enter' && handleSearch()}
        placeholder="Search packages..."
        class="flex h-10 w-full md:w-96 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
      />
      
      <select
        bind:value={selectedCategory}
        onchange={handleSearch}
        class="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      >
        {#each categories as category}
          <option value={category.value}>{category.label}</option>
        {/each}
      </select>
      
      <select
        bind:value={selectedPricing}
        onchange={handleSearch}
        class="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      >
        {#each pricingModels as pricing}
          <option value={pricing.value}>{pricing.label}</option>
        {/each}
      </select>
    </div>
  </div>
  
  <!-- Featured Packages -->
  {#if featured.length > 0 && !filters.query && !filters.category}
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-12">
      <h2 class="text-2xl font-bold mb-6">Featured Packages</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {#each featured as pkg (pkg.id)}
          <Card>
            <CardHeader>
              <div class="flex items-start justify-between">
                <div class="flex items-center gap-3">
                  {#if pkg.icon_url}
                    <img src={pkg.icon_url} alt={pkg.name} class="w-12 h-12 rounded" />
                  {/if}
                  <div>
                    <div class="flex items-center gap-2">
                      <CardTitle class="text-lg">{pkg.name}</CardTitle>
                      {#if pkg.is_verified}
                        <Verified class="w-4 h-4 text-primary" />
                      {/if}
                    </div>
                    <p class="text-sm text-muted-foreground capitalize">{pkg.category.replace('_', ' ')}</p>
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <p class="text-sm text-muted-foreground mb-4">{pkg.description}</p>
              
              <div class="flex items-center justify-between text-sm mb-4">
                <div class="flex items-center gap-1">
                  <Star class="w-4 h-4 fill-yellow-400 text-yellow-400" />
                  <span class="font-medium">{pkg.rating_avg?.toFixed(1)}</span>
                  <span class="text-muted-foreground">({pkg.rating_count})</span>
                </div>
                <div class="flex items-center gap-1 text-muted-foreground">
                  <Download class="w-4 h-4" />
                  <span>{formatInstalls(pkg.install_count)}</span>
                </div>
              </div>
              
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-primary">{formatPrice(pkg)}</span>
                <Button
                  onclick={() => router.visit(`/marketplace/${pkg.slug}`)}
                  size="sm"
                >
                  View Details
                </Button>
              </div>
            </CardContent>
          </Card>
        {/each}
      </div>
    </div>
  {/if}
  
  <!-- All Packages -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-16">
    <h2 class="text-2xl font-bold mb-6">
      {filters.query || filters.category ? 'Search Results' : 'All Packages'}
    </h2>
    
    {#if packages.length === 0}
      <div class="text-center py-12">
        <p class="text-muted-foreground">No packages found matching your criteria.</p>
        <Button onclick={() => router.visit('/marketplace')} variant="outline" class="mt-4">
          Clear Filters
        </Button>
      </div>
    {:else}
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {#each packages as pkg (pkg.id)}
          <Card>
            <CardHeader>
              <div class="flex items-start justify-between">
                <div class="flex items-center gap-3">
                  {#if pkg.icon_url}
                    <img src={pkg.icon_url} alt={pkg.name} class="w-12 h-12 rounded" />
                  {/if}
                  <div>
                    <div class="flex items-center gap-2">
                      <CardTitle class="text-lg">{pkg.name}</CardTitle>
                      {#if pkg.is_verified}
                        <Verified class="w-4 h-4 text-primary" />
                      {/if}
                    </div>
                    <p class="text-sm text-muted-foreground capitalize">{pkg.category.replace('_', ' ')}</p>
                  </div>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <p class="text-sm text-muted-foreground mb-4">{pkg.description}</p>
              
              <div class="flex items-center justify-between text-sm mb-4">
                <div class="flex items-center gap-1">
                  <Star class="w-4 h-4 fill-yellow-400 text-yellow-400" />
                  <span class="font-medium">{pkg.rating_avg?.toFixed(1)}</span>
                  <span class="text-muted-foreground">({pkg.rating_count})</span>
                </div>
                <div class="flex items-center gap-1 text-muted-foreground">
                  <Download class="w-4 h-4" />
                  <span>{formatInstalls(pkg.install_count)}</span>
                </div>
              </div>
              
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-primary">{formatPrice(pkg)}</span>
                <Button
                  onclick={() => router.visit(`/marketplace/${pkg.slug}`)}
                  size="sm"
                >
                  View Details
                </Button>
              </div>
            </CardContent>
          </Card>
        {/each}
      </div>
    {/if}
  </div>
</div>
```

## Verification Checklist

- [ ] Package resource created
- [ ] Installation resource created
- [ ] Package installer job works
- [ ] Migrations run successfully
- [ ] Seed data creates packages
- [ ] Marketplace page renders
- [ ] Package cards display correctly
- [ ] Search and filtering works
- [ ] shadcn-svelte components work

## Next Phase

**Phase 3: Chat Interface with Streaming** (Inertia + Svelte version)

---

**Completion Status:** Phase 2 creates the package marketplace with beautiful Svelte UI.
