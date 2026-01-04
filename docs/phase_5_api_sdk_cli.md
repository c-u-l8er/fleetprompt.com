# FleetPrompt - Phase 5: API, SDK & Developer Tools

## Overview
This phase implements the developer-facing API, SDKs, CLI tools, and documentation needed to make FleetPrompt a fully functional platform that developers can integrate into their applications.

## Prerequisites
- ✅ Phases 0-4 completed
- ✅ All core resources functional
- ✅ Executions working

## Phase 5 Goals

1. ✅ Create REST API with AshJsonApi
2. ✅ Build GraphQL API (optional)
3. ✅ Create TypeScript SDK
4. ✅ Build CLI tool
5. ✅ Implement API authentication
6. ✅ Create webhooks system
7. ✅ Build API documentation
8. ✅ Add rate limiting

## Backend Implementation

### Step 1: Configure AshJsonApi

Update `config/config.exs`:

```elixir
config :fleet_prompt, :ash_domains,
  [
    FleetPrompt.Accounts,
    FleetPrompt.Agents,
    FleetPrompt.Skills,
    FleetPrompt.Workflows,
    FleetPrompt.Packages
  ]

config :mime, :types, %{
  "application/vnd.api+json" => ["json"]
}
```

### Step 2: Add JSON API to Resources

Update `lib/fleet_prompt/agents/agent.ex`:

```elixir
defmodule FleetPrompt.Agents.Agent do
  use Ash.Resource,
    domain: FleetPrompt.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshJsonApi.Resource]  # Add this

  # ... existing code ...

  json_api do
    type "agent"
    
    routes do
      base "/agents"
      
      get :read
      index :read
      post :create
      patch :update
      delete :destroy
      
      # Custom routes
      post :deploy, route: "/:id/deploy"
      post :execute, route: "/:id/execute"
    end
  end
  
  # ... rest of resource ...
end
```

Update other resources similarly (Package, Execution, Workflow, etc.)

### Step 3: Create API Router

Create `lib/fleet_prompt_web/api_router.ex`:

```elixir
defmodule FleetPromptWeb.ApiRouter do
  use AshJsonApi.Router,
    domains: [
      FleetPrompt.Accounts,
      FleetPrompt.Agents,
      FleetPrompt.Skills,
      FleetPrompt.Workflows,
      FleetPrompt.Packages
    ],
    open_api: "/open_api"
end
```

### Step 4: Create API Authentication

Create `lib/fleet_prompt/accounts/api_key.ex`:

```elixir
defmodule FleetPrompt.Accounts.ApiKey do
  use Ash.Resource,
    domain: FleetPrompt.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "api_keys"
    repo FleetPrompt.Repo
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :key_hash, :string do
      allow_nil? false
      private? true
    end
    
    attribute :key_prefix, :string do
      allow_nil? false
      public? true
    end
    
    attribute :name, :string do
      allow_nil? false
      public? true
    end
    
    attribute :scopes, {:array, :atom} do
      default [:read, :write]
      public? true
    end
    
    attribute :last_used_at, :utc_datetime_usec do
      public? true
    end
    
    attribute :expires_at, :utc_datetime_usec do
      public? true
    end
    
    attribute :is_active, :boolean do
      default true
      public? true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :update, :destroy]
    
    create :create do
      accept [:name, :scopes, :expires_at]
      argument :organization_id, :uuid, allow_nil? false
      
      change fn changeset, _context ->
        # Generate API key
        key = generate_api_key()
        key_hash = hash_key(key)
        key_prefix = String.slice(key, 0..7)
        
        # Store key in changeset metadata so we can return it
        changeset
        |> Ash.Changeset.force_change_attribute(:key_hash, key_hash)
        |> Ash.Changeset.force_change_attribute(:key_prefix, key_prefix)
        |> Ash.Changeset.set_context(%{generated_key: key})
      end
      
      after_action fn _changeset, api_key, context ->
        # Return the generated key (only time it's visible)
        {:ok, Map.put(api_key, :key, context.generated_key)}
      end
    end
    
    update :mark_used do
      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :last_used_at, DateTime.utc_now())
      end
    end
  end
  
  relationships do
    belongs_to :organization, FleetPrompt.Accounts.Organization
    belongs_to :user, FleetPrompt.Accounts.User
  end
  
  defp generate_api_key do
    prefix = "fp"
    random = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    "#{prefix}_#{random}"
  end
  
  defp hash_key(key) do
    :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
  end
end
```

### Step 5: Create API Authentication Plug

Create `lib/fleet_prompt_web/plugs/api_auth.ex`:

```elixir
defmodule FleetPromptWeb.Plugs.ApiAuth do
  import Plug.Conn
  
  alias FleetPrompt.Accounts.ApiKey
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    with {:ok, token} <- get_bearer_token(conn),
         {:ok, api_key} <- verify_api_key(token),
         {:ok, organization} <- load_organization(api_key) do
      
      # Update last used
      api_key
      |> Ash.Changeset.for_update(:mark_used)
      |> Ash.update()
      
      conn
      |> assign(:current_api_key, api_key)
      |> assign(:current_organization, organization)
      |> assign(:current_user, api_key.user)
    else
      {:error, :missing_token} ->
        unauthorized(conn, "Missing API key")
      {:error, :invalid_token} ->
        unauthorized(conn, "Invalid API key")
      {:error, :expired} ->
        unauthorized(conn, "API key expired")
    end
  end
  
  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end
  
  defp verify_api_key(token) do
    key_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    
    case ApiKey
         |> Ash.Query.filter(key_hash == ^key_hash and is_active == true)
         |> Ash.read_one() do
      {:ok, api_key} ->
        if expired?(api_key) do
          {:error, :expired}
        else
          {:ok, api_key}
        end
      _ ->
        {:error, :invalid_token}
    end
  end
  
  defp expired?(api_key) do
    api_key.expires_at && DateTime.compare(DateTime.utc_now(), api_key.expires_at) == :gt
  end
  
  defp load_organization(api_key) do
    case FleetPrompt.Accounts.Organization |> Ash.get(api_key.organization_id) do
      {:ok, org} -> {:ok, org}
      _ -> {:error, :invalid_token}
    end
  end
  
  defp unauthorized(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: message}))
    |> halt()
  end
end
```

### Step 6: Update Router for API

Update `lib/fleet_prompt_web/router.ex`:

```elixir
defmodule FleetPromptWeb.Router do
  use FleetPromptWeb, :router
  use AshAuthentication.Phoenix.Router

  # ... existing pipelines ...

  pipeline :api do
    plug :accepts, ["json", "json-api"]
    plug FleetPromptWeb.Plugs.ApiAuth
  end

  # Browser routes
  scope "/", FleetPromptWeb do
    pipe_through :browser
    
    get "/", ChatController, :index
    post "/chat/send", ChatController, :send_message
    
    get "/marketplace", MarketplaceController, :index
    get "/marketplace/:slug", MarketplaceController, :show
    
    get "/executions", ExecutionController, :index
    get "/executions/:id", ExecutionController, :show
  end

  # API routes
  scope "/api/v1" do
    pipe_through :api
    
    forward "/", FleetPromptWeb.ApiRouter
  end

  # OpenAPI documentation
  scope "/api" do
    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/v1/open_api"
  end
end
```

### Step 7: Create Webhook System

Create `lib/fleet_prompt/webhooks/webhook.ex`:

```elixir
defmodule FleetPrompt.Webhooks.Webhook do
  use Ash.Resource,
    domain: FleetPrompt.Webhooks,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "webhooks"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :url, :string do
      allow_nil? false
      public? true
    end
    
    attribute :events, {:array, :atom} do
      constraints items: [
        one_of: [
          :agent_executed,
          :agent_failed,
          :workflow_completed,
          :package_installed,
          :execution_completed
        ]
      ]
      allow_nil? false
      public? true
    end
    
    attribute :secret, :string do
      allow_nil? false
      sensitive? true
    end
    
    attribute :is_active, :boolean do
      default true
      public? true
    end
    
    attribute :last_triggered_at, :utc_datetime_usec do
      public? true
    end
    
    attribute :failure_count, :integer do
      default 0
      public? true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create do
      accept [:url, :events]
      
      change fn changeset, _context ->
        # Generate webhook secret
        secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
        
        Ash.Changeset.force_change_attribute(changeset, :secret, secret)
      end
    end
  end
  
  relationships do
    belongs_to :organization, FleetPrompt.Accounts.Organization
  end
end
```

Create `lib/fleet_prompt/webhooks/delivery.ex`:

```elixir
defmodule FleetPrompt.Webhooks.Delivery do
  @moduledoc """
  Handles webhook deliveries
  """
  
  def deliver(webhook, event, payload) do
    signature = sign_payload(payload, webhook.secret)
    
    case Req.post(webhook.url,
      json: %{
        event: event,
        payload: payload,
        timestamp: DateTime.utc_now()
      },
      headers: [
        {"x-fleetprompt-signature", signature},
        {"x-fleetprompt-event", to_string(event)}
      ],
      retry: [max_retries: 3, delay: 1000]
    ) do
      {:ok, %{status: status}} when status in 200..299 ->
        # Success
        webhook
        |> Ash.Changeset.for_update(:update, %{
          last_triggered_at: DateTime.utc_now(),
          failure_count: 0
        })
        |> Ash.update()
        
        :ok
        
      _ ->
        # Failure
        webhook
        |> Ash.Changeset.for_update(:update, %{
          failure_count: webhook.failure_count + 1
        })
        |> Ash.update()
        
        {:error, :delivery_failed}
    end
  end
  
  defp sign_payload(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, Jason.encode!(payload))
    |> Base.encode16(case: :lower)
  end
end
```

### Step 8: Create Rate Limiting

Create `lib/fleet_prompt_web/plugs/rate_limit.ex`:

```elixir
defmodule FleetPromptWeb.Plugs.RateLimit do
  import Plug.Conn
  
  @rate_limit 1000  # requests per hour
  @rate_window 3600  # 1 hour in seconds
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    api_key = conn.assigns[:current_api_key]
    
    if api_key do
      key = "rate_limit:#{api_key.id}"
      
      case check_rate_limit(key) do
        {:ok, remaining} ->
          conn
          |> put_resp_header("x-ratelimit-limit", "#{@rate_limit}")
          |> put_resp_header("x-ratelimit-remaining", "#{remaining}")
          
        {:error, :rate_limited} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(429, Jason.encode!(%{
            error: "Rate limit exceeded",
            limit: @rate_limit,
            window: @rate_window
          }))
          |> halt()
      end
    else
      conn
    end
  end
  
  defp check_rate_limit(key) do
    # Using simple ETS-based rate limiting
    # In production, use Redis or Hammer library
    
    current = :ets.update_counter(:rate_limits, key, {2, 1}, {key, 0, now()})
    
    if current > @rate_limit do
      {:error, :rate_limited}
    else
      {:ok, @rate_limit - current}
    end
  end
  
  defp now, do: System.system_time(:second)
end
```

## SDK & CLI Implementation

### Step 9: Create TypeScript SDK

Create `sdk/typescript/package.json`:

```json
{
  "name": "@fleetprompt/sdk",
  "version": "1.0.0",
  "description": "TypeScript SDK for FleetPrompt",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "test": "jest",
    "prepublishOnly": "npm run build"
  },
  "dependencies": {
    "axios": "^1.6.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "^5.0.0"
  }
}
```

Create `sdk/typescript/src/index.ts`:

```typescript
import axios, { AxiosInstance } from 'axios';

export interface FleetPromptConfig {
  apiKey: string;
  baseURL?: string;
}

export interface Agent {
  id: string;
  name: string;
  description: string;
  status: 'draft' | 'active' | 'paused';
  config: {
    model: string;
    max_tokens: number;
    temperature: number;
  };
}

export interface Execution {
  id: string;
  status: 'queued' | 'running' | 'completed' | 'failed';
  input: Record<string, any>;
  output?: Record<string, any>;
  latency_ms?: number;
  total_tokens?: number;
  cost_usd?: string;
}

export interface Package {
  id: string;
  name: string;
  slug: string;
  description: string;
  category: string;
  pricing_model: string;
}

export class FleetPromptClient {
  private client: AxiosInstance;

  constructor(config: FleetPromptConfig) {
    this.client = axios.create({
      baseURL: config.baseURL || 'https://api.fleetprompt.com/api/v1',
      headers: {
        'Authorization': `Bearer ${config.apiKey}`,
        'Content-Type': 'application/vnd.api+json',
      },
    });
  }

  // Agents
  async listAgents(): Promise<Agent[]> {
    const response = await this.client.get('/agents');
    return response.data.data;
  }

  async getAgent(id: string): Promise<Agent> {
    const response = await this.client.get(`/agents/${id}`);
    return response.data.data;
  }

  async createAgent(data: Partial<Agent>): Promise<Agent> {
    const response = await this.client.post('/agents', {
      data: {
        type: 'agent',
        attributes: data,
      },
    });
    return response.data.data;
  }

  async updateAgent(id: string, data: Partial<Agent>): Promise<Agent> {
    const response = await this.client.patch(`/agents/${id}`, {
      data: {
        type: 'agent',
        id,
        attributes: data,
      },
    });
    return response.data.data;
  }

  async deleteAgent(id: string): Promise<void> {
    await this.client.delete(`/agents/${id}`);
  }

  async deployAgent(id: string): Promise<Agent> {
    const response = await this.client.post(`/agents/${id}/deploy`);
    return response.data.data;
  }

  // Executions
  async executeAgent(agentId: string, input: Record<string, any>): Promise<Execution> {
    const response = await this.client.post(`/agents/${agentId}/execute`, {
      data: {
        type: 'execution',
        attributes: { input },
      },
    });
    return response.data.data;
  }

  async getExecution(id: string): Promise<Execution> {
    const response = await this.client.get(`/executions/${id}`);
    return response.data.data;
  }

  async listExecutions(agentId?: string): Promise<Execution[]> {
    const params = agentId ? { filter: { agent_id: agentId } } : {};
    const response = await this.client.get('/executions', { params });
    return response.data.data;
  }

  // Packages
  async listPackages(filters?: { category?: string; pricing?: string }): Promise<Package[]> {
    const response = await this.client.get('/packages', { params: filters });
    return response.data.data;
  }

  async getPackage(slug: string): Promise<Package> {
    const response = await this.client.get(`/packages/${slug}`);
    return response.data.data;
  }

  async installPackage(packageId: string, config?: Record<string, any>): Promise<any> {
    const response = await this.client.post('/installations', {
      data: {
        type: 'installation',
        attributes: { package_id: packageId, config },
      },
    });
    return response.data.data;
  }

  // Workflows
  async createWorkflow(data: any): Promise<any> {
    const response = await this.client.post('/workflows', {
      data: {
        type: 'workflow',
        attributes: data,
      },
    });
    return response.data.data;
  }

  async runWorkflow(workflowId: string, input: Record<string, any>): Promise<any> {
    const response = await this.client.post('/workflow-runs', {
      data: {
        type: 'workflow-run',
        attributes: { workflow_id: workflowId, input },
      },
    });
    return response.data.data;
  }
}

export default FleetPromptClient;
```

### Step 10: Create CLI Tool

Create `cli/package.json`:

```json
{
  "name": "@fleetprompt/cli",
  "version": "1.0.0",
  "description": "FleetPrompt CLI",
  "bin": {
    "fleet": "./dist/cli.js"
  },
  "scripts": {
    "build": "tsc",
    "prepublishOnly": "npm run build"
  },
  "dependencies": {
    "@fleetprompt/sdk": "^1.0.0",
    "commander": "^11.0.0",
    "inquirer": "^9.0.0",
    "chalk": "^5.0.0",
    "ora": "^7.0.0"
  }
}
```

Create `cli/src/cli.ts`:

```typescript
#!/usr/bin/env node

import { Command } from 'commander';
import inquirer from 'inquirer';
import chalk from 'chalk';
import ora from 'ora';
import { FleetPromptClient } from '@fleetprompt/sdk';
import fs from 'fs';
import path from 'path';

const program = new Command();

// Load config
function loadConfig() {
  const configPath = path.join(process.env.HOME!, '.fleetprompt', 'config.json');
  
  if (fs.existsSync(configPath)) {
    return JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  }
  
  return null;
}

function saveConfig(config: any) {
  const configDir = path.join(process.env.HOME!, '.fleetprompt');
  
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(configDir, 'config.json'),
    JSON.stringify(config, null, 2)
  );
}

function getClient() {
  const config = loadConfig();
  
  if (!config?.apiKey) {
    console.error(chalk.red('Not authenticated. Run: fleet login'));
    process.exit(1);
  }
  
  return new FleetPromptClient({
    apiKey: config.apiKey,
    baseURL: config.baseURL,
  });
}

program
  .name('fleet')
  .description('FleetPrompt CLI - Deploy AI agent fleets')
  .version('1.0.0');

// Login
program
  .command('login')
  .description('Authenticate with FleetPrompt')
  .action(async () => {
    const answers = await inquirer.prompt([
      {
        type: 'input',
        name: 'apiKey',
        message: 'Enter your API key:',
      },
      {
        type: 'input',
        name: 'baseURL',
        message: 'API URL (press enter for default):',
        default: 'https://api.fleetprompt.com/api/v1',
      },
    ]);
    
    saveConfig(answers);
    console.log(chalk.green('✓ Authenticated successfully'));
  });

// List agents
program
  .command('agents:list')
  .alias('agents')
  .description('List all agents')
  .action(async () => {
    const spinner = ora('Loading agents...').start();
    const client = getClient();
    
    try {
      const agents = await client.listAgents();
      spinner.succeed('Agents loaded');
      
      console.log('\n' + chalk.bold('Your Agents:'));
      agents.forEach(agent => {
        console.log(`  ${chalk.cyan(agent.name)} (${agent.status})`);
        console.log(`  ID: ${agent.id}`);
        console.log(`  Model: ${agent.config.model}\n`);
      });
    } catch (error) {
      spinner.fail('Failed to load agents');
      console.error(chalk.red(error));
    }
  });

// Create agent
program
  .command('agents:create')
  .description('Create a new agent')
  .action(async () => {
    const answers = await inquirer.prompt([
      {
        type: 'input',
        name: 'name',
        message: 'Agent name:',
        validate: (input) => input.length > 0,
      },
      {
        type: 'input',
        name: 'description',
        message: 'Description:',
      },
      {
        type: 'editor',
        name: 'system_prompt',
        message: 'System prompt:',
      },
      {
        type: 'list',
        name: 'model',
        message: 'Model:',
        choices: ['claude-sonnet-4', 'claude-opus-4', 'gpt-4'],
      },
    ]);
    
    const spinner = ora('Creating agent...').start();
    const client = getClient();
    
    try {
      const agent = await client.createAgent({
        ...answers,
        config: {
          model: answers.model,
          max_tokens: 4096,
          temperature: 0.7,
        },
      });
      
      spinner.succeed('Agent created');
      console.log(chalk.green(`\n✓ Created agent: ${agent.name}`));
      console.log(`  ID: ${agent.id}`);
    } catch (error) {
      spinner.fail('Failed to create agent');
      console.error(chalk.red(error));
    }
  });

// Deploy agent
program
  .command('agents:deploy <agent-id>')
  .description('Deploy an agent')
  .action(async (agentId) => {
    const spinner = ora('Deploying agent...').start();
    const client = getClient();
    
    try {
      await client.deployAgent(agentId);
      spinner.succeed('Agent deployed');
    } catch (error) {
      spinner.fail('Failed to deploy agent');
      console.error(chalk.red(error));
    }
  });

// Execute agent
program
  .command('agents:execute <agent-id>')
  .description('Execute an agent')
  .option('-i, --input <json>', 'Input as JSON string')
  .action(async (agentId, options) => {
    const input = options.input ? JSON.parse(options.input) : {};
    
    const spinner = ora('Executing agent...').start();
    const client = getClient();
    
    try {
      const execution = await client.executeAgent(agentId, input);
      spinner.succeed('Execution started');
      
      console.log(chalk.green(`\nExecution ID: ${execution.id}`));
      console.log(`Status: ${execution.status}`);
      
      // Poll for completion
      const pollSpinner = ora('Waiting for completion...').start();
      
      let completed = false;
      while (!completed) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        const status = await client.getExecution(execution.id);
        
        if (status.status === 'completed') {
          pollSpinner.succeed('Execution completed');
          console.log('\nOutput:');
          console.log(JSON.stringify(status.output, null, 2));
          completed = true;
        } else if (status.status === 'failed') {
          pollSpinner.fail('Execution failed');
          process.exit(1);
        }
      }
    } catch (error) {
      spinner.fail('Failed to execute agent');
      console.error(chalk.red(error));
    }
  });

// Install package
program
  .command('packages:install <slug>')
  .description('Install a package')
  .action(async (slug) => {
    const spinner = ora('Installing package...').start();
    const client = getClient();
    
    try {
      const pkg = await client.getPackage(slug);
      const installation = await client.installPackage(pkg.id);
      
      spinner.succeed(`Package "${pkg.name}" installed`);
      console.log(`  Installation ID: ${installation.id}`);
    } catch (error) {
      spinner.fail('Failed to install package');
      console.error(chalk.red(error));
    }
  });

program.parse();
```

### Step 11: Create API Documentation Page

Create `assets/src/pages/Docs/Api.svelte`:

```svelte
<script lang="ts">
  interface Props {
    openapi_url: string;
  }
  
  let { openapi_url }: Props = $props();
</script>

<div class="min-h-screen bg-background">
  <div class="border-b">
    <div class="max-w-7xl mx-auto px-8 py-8">
      <h1 class="text-4xl font-bold mb-2">API Documentation</h1>
      <p class="text-muted-foreground text-lg">
        Complete API reference for FleetPrompt
      </p>
    </div>
  </div>
  
  <div class="max-w-7xl mx-auto px-8 py-12">
    <div class="grid md:grid-cols-2 gap-8 mb-12">
      <div class="p-6 border rounded-lg">
        <h2 class="text-2xl font-bold mb-4">Getting Started</h2>
        <p class="text-muted-foreground mb-4">
          Authenticate using API keys in the Authorization header:
        </p>
        <pre class="bg-muted p-4 rounded text-sm overflow-x-auto"><code>Authorization: Bearer fp_your_api_key_here</code></pre>
      </div>
      
      <div class="p-6 border rounded-lg">
        <h2 class="text-2xl font-bold mb-4">Base URL</h2>
        <p class="text-muted-foreground mb-4">
          All API requests should be made to:
        </p>
        <pre class="bg-muted p-4 rounded text-sm overflow-x-auto"><code>https://api.fleetprompt.com/api/v1</code></pre>
      </div>
    </div>
    
    <div class="prose prose-slate max-w-none">
      <h2>Quick Example</h2>
      <pre><code class="language-javascript">{`import FleetPromptClient from '@fleetprompt/sdk';

const client = new FleetPromptClient({
  apiKey: 'fp_your_api_key'
});

// Execute an agent
const execution = await client.executeAgent('agent-id', {
  message: 'Hello, world!'
});

console.log(execution.output);`}</code></pre>
      
      <h2>Rate Limits</h2>
      <p>
        API requests are rate limited to 1,000 requests per hour per API key.
        Rate limit information is included in response headers:
      </p>
      <ul>
        <li><code>X-RateLimit-Limit</code>: Maximum requests allowed</li>
        <li><code>X-RateLimit-Remaining</code>: Requests remaining in current window</li>
      </ul>
      
      <h2>Interactive Documentation</h2>
      <p>
        Explore the full API using our interactive Swagger UI:
      </p>
      <a href={openapi_url} class="text-primary hover:underline">
        Open API Explorer →
      </a>
    </div>
  </div>
</div>
```

## Verification Checklist

- [ ] REST API working
- [ ] API authentication functional
- [ ] Rate limiting implemented
- [ ] TypeScript SDK compiled
- [ ] CLI tool working
- [ ] Webhooks deliver successfully
- [ ] OpenAPI docs generated
- [ ] All endpoints documented

## Deployment

### Production Checklist

```bash
# Environment variables needed
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
DATABASE_URL=postgresql://...
SECRET_KEY_BASE=...
PHX_HOST=fleetprompt.com
PORT=4000

# Build frontend
cd assets && npm run build && cd ..

# Run migrations
mix ecto.migrate

# Start production server
MIX_ENV=prod mix phx.server
```

## Documentation Site

Create comprehensive docs site with:
- Getting started guide
- API reference
- SDK documentation
- CLI usage
- Code examples
- Tutorials

## Success Metrics

After Phase 5 completion, track:
- API requests per day
- SDK downloads
- CLI installations
- Active API keys
- Average response time
- Error rate

---

**🎉 Completion Status:** All 5 phases complete! FleetPrompt is now a fully functional AI agent platform with:
- ✅ Multi-tenant SaaS backend (Phoenix + Ash)
- ✅ Beautiful frontend (Svelte + Inertia + shadcn)
- ✅ Chat-based interaction
- ✅ Package marketplace
- ✅ Agent execution engine
- ✅ Workflow orchestration
- ✅ REST API
- ✅ TypeScript SDK
- ✅ CLI tool
- ✅ Webhooks
- ✅ Rate limiting

Ready for production deployment! 🚀
