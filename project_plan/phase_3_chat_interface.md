# FleetPrompt - Phase 3: Chat Interface with Streaming (Package-First + Signal-Driven)

## Overview
This phase implements FleetPrompt’s chat experience as a **package-first concierge** and **signal-driven command surface**.

The primary outcome of chat is NOT “a chatbot UI”, but a reliable way to:
- help users **discover** and **install** packages (the core product),
- translate natural language into **typed actions** (install, configure, deploy, run),
- emit **signals** that drive the rest of the platform (packages, agents, workflows, and future integrations),
- stream an assistant response while preserving a structured, auditable action trail.

Chat should feel like “talking to the Marketplace + Fleet control plane”, with the assistant generating **action buttons** that map to real backend commands (rather than free-form “do anything” tool execution).

## Prerequisites
- ✅ Phase 0 completed (Inertia + Svelte)
- ✅ Phase 1 completed (Core resources + org/tenant context)
- ◻️ Phase 2 in-progress or completed (Marketplace + installation primitives are strongly recommended before shipping Chat as the main CTA)

## Phase 3 Goals (Realigned)

1. ✅ Ship a chat UI with **streaming SSE** responses (fast feedback loop)
2. ✅ Persist conversations/messages with a stable **message + action** schema
3. ✅ Implement “package-first” intent routing:
   - package discovery, comparison, and install flow are the default “happy path”
4. ✅ Standardize **signal-driven actions**:
   - assistant proposes typed actions
   - backend validates, executes, and emits signals for downstream systems
5. ✅ Make actions composable and auditable:
   - every action has an id, type, payload, status, and resulting domain ids
6. ✅ Add safe “assistant as guide” behavior:
   - never silently mutate state; always surface an explicit action for installs/deploys/runs
7. ✅ Provide a clean migration path to Phase 4 (execution/workflows) without rewriting Chat:
   - Chat emits signals/commands; execution engines subscribe

## Architecture Overview (Signal-Driven)

```
User Input
  → Phoenix Controller (SSE)
    → Intent Router (package-first)
      → Plan (assistant response + typed actions)
        → (optional) Execute Action (explicit user click)
          → Domain Command (Packages/Agents/Workflows)
            → Signal Emission (audit + integrations)
  → Stream assistant text via SSE
  → Render actions (buttons) in Svelte UI
```

### Core Principle: Chat produces signals, not side effects
- The assistant can propose actions, but side effects happen only via explicit, validated commands.
- Every meaningful operation emits a signal that can later be consumed by:
  - observability/telemetry,
  - package lifecycle management,
  - workflow automation,
  - external integrations.

## Backend Implementation

### Step 1: Create Chat Message Resource

Create `lib/fleet_prompt/chat/message.ex`:

```elixir
defmodule FleetPrompt.Chat.Message do
  use Ash.Resource,
    domain: FleetPrompt.Chat,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "chat_messages"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :conversation_id, :uuid do
      allow_nil? false
      public? true
    end
    
    attribute :role, :atom do
      constraints one_of: [:user, :assistant]
      allow_nil? false
      public? true
    end
    
    attribute :content, :string do
      allow_nil? false
      public? true
    end
    
    attribute :intent, :atom do
      constraints one_of: [
        :general,
        :package_search,
        :package_install,
        :agent_create,
        :agent_deploy,
        :pricing_query,
        :help,
        :workflow_create
      ]
      public? true
    end
    
    attribute :metadata, :map do
      default %{}
      public? true
    end
    
    # Interactive actions attached to messages
    attribute :actions, {:array, :map} do
      default []
      public? true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create]
    
    create :create_with_conversation do
      accept [:role, :content, :intent, :metadata, :actions]
      argument :user_id, :uuid, allow_nil? false
      
      change fn changeset, context ->
        user_id = Ash.Changeset.get_argument(changeset, :user_id)
        
        # Get or create conversation
        conversation_id = get_or_create_conversation(user_id, context.tenant)
        
        Ash.Changeset.force_change_attribute(changeset, :conversation_id, conversation_id)
      end
    end
    
    read :by_conversation do
      argument :conversation_id, :uuid, allow_nil? false
      filter expr(conversation_id == ^arg(:conversation_id))
      prepare fn query, _context ->
        Ash.Query.sort(query, inserted_at: :asc)
      end
    end
  end
  
  relationships do
    belongs_to :user, FleetPrompt.Accounts.User
  end
  
  defp get_or_create_conversation(user_id, tenant) do
    # Simple: one conversation per user for now
    # In production, support multiple conversations
    case FleetPrompt.Chat.Conversation
         |> Ash.Query.filter(user_id == ^user_id)
         |> Ash.Query.set_tenant(tenant)
         |> Ash.read_one() do
      {:ok, conversation} -> conversation.id
      {:error, _} ->
        {:ok, conversation} = FleetPrompt.Chat.Conversation
          |> Ash.Changeset.for_create(:create, %{user_id: user_id})
          |> Ash.Changeset.set_tenant(tenant)
          |> Ash.create()
        conversation.id
    end
  end
end
```

### Step 2: Create Conversation Resource

Create `lib/fleet_prompt/chat/conversation.ex`:

```elixir
defmodule FleetPrompt.Chat.Conversation do
  use Ash.Resource,
    domain: FleetPrompt.Chat,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "chat_conversations"
    repo FleetPrompt.Repo
  end
  
  multitenancy do
    strategy :context
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :title, :string do
      public? true
    end
    
    attribute :last_message_at, :utc_datetime_usec do
      public? true
    end
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
  end
  
  relationships do
    belongs_to :user, FleetPrompt.Accounts.User
    has_many :messages, FleetPrompt.Chat.Message
  end
end
```

### Step 3: Create Intent Classifier

Create `lib/fleet_prompt/ai/intent_classifier.ex`:

```elixir
defmodule FleetPrompt.AI.IntentClassifier do
  @moduledoc """
  Classifies user intent from chat messages.
  Uses pattern matching and keywords for fast classification.
  """
  
  def classify(message) do
    lower = String.downcase(message)
    
    cond do
      matches_package_search?(lower) -> :package_search
      matches_package_install?(lower) -> :package_install
      matches_agent_create?(lower) -> :agent_create
      matches_agent_deploy?(lower) -> :agent_deploy
      matches_pricing?(lower) -> :pricing_query
      matches_help?(lower) -> :help
      matches_workflow?(lower) -> :workflow_create
      true -> :general
    end
  end
  
  defp matches_package_search?(text) do
    keywords = ["package", "packages", "marketplace", "browse", "show me", "find", "search"]
    Enum.any?(keywords, &String.contains?(text, &1))
  end
  
  defp matches_package_install?(text) do
    keywords = ["install", "deploy", "add", "use"]
    has_keyword = Enum.any?(keywords, &String.contains?(text, &1))
    has_package = String.contains?(text, "package")
    
    has_keyword and has_package
  end
  
  defp matches_agent_create?(text) do
    keywords = ["create agent", "build agent", "make agent", "new agent"]
    Enum.any?(keywords, &String.contains?(text, &1))
  end
  
  defp matches_agent_deploy?(text) do
    keywords = ["deploy", "start", "launch", "activate"]
    has_keyword = Enum.any?(keywords, &String.contains?(text, &1))
    has_agent = String.contains?(text, "agent")
    
    has_keyword and has_agent
  end
  
  defp matches_pricing?(text) do
    keywords = ["price", "pricing", "cost", "how much", "tier", "plan"]
    Enum.any?(keywords, &String.contains?(text, &1))
  end
  
  defp matches_help?(text) do
    keywords = ["help", "how to", "tutorial", "guide", "documentation"]
    Enum.any?(keywords, &String.contains?(text, &1))
  end
  
  defp matches_workflow?(text) do
    keywords = ["workflow", "automation", "process", "sequence"]
    Enum.any?(keywords, &String.contains?(text, &1))
  end
end
```

### Step 4: Create Response Handlers

Create `lib/fleet_prompt/ai/response_handlers.ex`:

```elixir
defmodule FleetPrompt.AI.ResponseHandlers do
  @moduledoc """
  Handles different types of chat responses with streaming support.
  """
  
  alias FleetPrompt.Packages.Package
  
  def handle_package_search(query, stream_fn) do
    stream_fn.("Let me search for packages related to '#{query}'...\n\n")
    
    # Search packages
    packages = Package
               |> Ash.Query.for_read(:search, %{query: query})
               |> Ash.Query.limit(5)
               |> Ash.read!()
    
    if Enum.empty?(packages) do
      stream_fn.("I couldn't find any packages matching '#{query}'. ")
      stream_fn.("Would you like to browse all available packages?")
      
      actions = [
        %{type: "navigate", path: "/marketplace", label: "Browse Marketplace"}
      ]
      {nil, actions}
    else
      stream_fn.("I found #{length(packages)} package(s):\n\n")
      
      actions = for pkg <- packages do
        stream_fn.("**#{pkg.name}**\n")
        stream_fn.("#{pkg.description}\n")
        stream_fn.("💰 #{format_price(pkg)} • ⭐ #{pkg.rating_avg}/5 (#{pkg.rating_count} reviews)\n\n")
        
        %{
          type: "view_package",
          package_slug: pkg.slug,
          label: "View #{pkg.name}"
        }
      end
      
      {nil, actions}
    end
  end
  
  def handle_package_install(package_name, stream_fn) do
    # Find package
    package = Package
              |> Ash.Query.filter(contains(name, ^package_name))
              |> Ash.read_one()
    
    case package do
      {:ok, pkg} ->
        stream_fn.("Great choice! I'll help you install **#{pkg.name}**.\n\n")
        stream_fn.("This package includes:\n")
        
        for agent <- pkg.includes["agents"] || [] do
          stream_fn.("• #{agent["name"]}: #{agent["description"]}\n")
        end
        
        stream_fn.("\n💰 Pricing: #{format_price(pkg)}\n")
        stream_fn.("📦 Installs: #{pkg.install_count}\n")
        stream_fn.("⭐ Rating: #{pkg.rating_avg}/5\n\n")
        
        actions = [
          %{
            type: "install_package",
            package_id: pkg.id,
            label: "Install Now",
            variant: "default"
          },
          %{
            type: "view_package",
            package_slug: pkg.slug,
            label: "View Details",
            variant: "outline"
          }
        ]
        
        {nil, actions}
        
      {:error, _} ->
        stream_fn.("I couldn't find a package matching '#{package_name}'. ")
        stream_fn.("Would you like to search the marketplace?")
        
        actions = [
          %{type: "navigate", path: "/marketplace", label: "Browse Marketplace"}
        ]
        
        {nil, actions}
    end
  end
  
  def handle_agent_create(description, stream_fn) do
    stream_fn.("I'll help you create a custom agent! 🤖\n\n")
    stream_fn.("Based on your description, here's what I recommend:\n\n")
    stream_fn.("**Agent Configuration:**\n")
    stream_fn.("• **Purpose:** #{description}\n")
    stream_fn.("• **Model:** claude-sonnet-4 (recommended)\n")
    stream_fn.("• **Skills:** Web search, data analysis\n\n")
    
    stream_fn.("To configure your agent, I need a few more details:\n")
    stream_fn.("1. What specific tasks should it handle?\n")
    stream_fn.("2. What tools does it need access to?\n")
    stream_fn.("3. Any specific instructions or constraints?\n")
    
    actions = [
      %{
        type: "start_agent_builder",
        description: description,
        label: "Configure Agent",
        variant: "default"
      }
    ]
    
    {nil, actions}
  end
  
  def handle_pricing_query(stream_fn) do
    stream_fn.("FleetPrompt offers flexible pricing tiers:\n\n")
    
    stream_fn.("**Free Tier** - $0/month\n")
    stream_fn.("• 100K tokens/month\n")
    stream_fn.("• 3 agents\n")
    stream_fn.("• Core packages\n")
    stream_fn.("• Community support\n\n")
    
    stream_fn.("**Pro Tier** - $49/month\n")
    stream_fn.("• 1M tokens/month\n")
    stream_fn.("• Unlimited agents\n")
    stream_fn.("• All packages & workflows\n")
    stream_fn.("• Priority support\n\n")
    
    stream_fn.("**Enterprise** - Custom pricing\n")
    stream_fn.("• Unlimited everything\n")
    stream_fn.("• Dedicated infrastructure\n")
    stream_fn.("• SLA guarantees\n")
    stream_fn.("• Custom integrations\n")
    
    actions = [
      %{type: "start_trial", label: "Start Free Trial", variant: "default"},
      %{type: "navigate", path: "/pricing", label: "View Full Pricing", variant: "outline"}
    ]
    
    {nil, actions}
  end
  
  def handle_general(message, conversation_history, stream_fn) do
    # Call actual LLM (Claude/GPT) for general queries
    # This is a placeholder - implement actual LLM integration
    
    response = """
    I'm FleetPrompt's AI assistant. I can help you:
    
    • Browse and install pre-built agent packages
    • Create custom agents from scratch
    • Deploy and manage agent fleets
    • Build multi-agent workflows
    • Answer questions about pricing and features
    
    What would you like to do?
    """
    
    stream_fn.(response)
    
    {nil, []}
  end
  
  defp format_price(%{pricing_model: :free}), do: "Free"
  defp format_price(%{pricing_model: :freemium}), do: "Free tier available"
  defp format_price(%{pricing_model: :paid, pricing_config: %{"price" => price}}), do: "$#{price}/mo"
  defp format_price(%{pricing_model: :revenue_share, pricing_config: %{"percentage" => pct}}), do: "#{pct}% revenue share"
  defp format_price(_), do: "Custom pricing"
end
```

### Step 5: Create Chat Controller with SSE

Create `lib/fleet_prompt_web/controllers/chat_controller.ex`:

```elixir
defmodule FleetPromptWeb.ChatController do
  use FleetPromptWeb, :controller
  
  alias FleetPrompt.Chat.{Message, Conversation}
  alias FleetPrompt.AI.{IntentClassifier, ResponseHandlers}
  
  def index(conn, _params) do
    current_user = conn.assigns[:current_user]
    current_org = conn.assigns[:current_org]
    
    # Load conversation history
    messages = if current_user && current_org do
      load_conversation_history(current_user.id, current_org)
    else
      # Guest user - show welcome message
      [
        %{
          id: "welcome",
          role: :assistant,
          content: """
          Welcome to **FleetPrompt**! 👋
          
          I can help you build and deploy AI agent fleets in minutes. You can:
          
          • Deploy pre-built packages (field service, customer support, sales)
          • Create custom agents from scratch
          • Build workflows with multiple agents
          • Browse the agent marketplace
          
          Try asking: *"Show me field service packages"* or *"Create a customer support agent"*
          """,
          actions: [],
          inserted_at: DateTime.utc_now()
        }
      ]
    end
    
    render_inertia(conn, "Chat/Index",
      props: %{
        messages: serialize_messages(messages),
        user: current_user && serialize_user(current_user)
      }
    )
  end
  
  def send_message(conn, %{"message" => content}) do
    current_user = conn.assigns[:current_user]
    current_org = conn.assigns[:current_org]
    
    unless current_user && current_org do
      conn
      |> put_status(401)
      |> json(%{error: "Authentication required"})
    else
      # Save user message
      {:ok, user_message} = Message
        |> Ash.Changeset.for_create(:create_with_conversation, %{
          role: :user,
          content: content,
          user_id: current_user.id
        })
        |> Ash.Changeset.set_tenant(current_org)
        |> Ash.create()
      
      # Classify intent
      intent = IntentClassifier.classify(content)
      
      # Stream response using SSE
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)
      |> stream_response(intent, content, user_message.conversation_id, current_user, current_org)
    end
  end
  
  defp stream_response(conn, intent, content, conversation_id, user, org) do
    # Create assistant message
    message_id = Ecto.UUID.generate()
    accumulated_content = ""
    actions = []
    
    # Streaming function
    stream_fn = fn chunk ->
      accumulated_content = accumulated_content <> chunk
      
      # Send SSE chunk
      chunk(conn, format_sse_chunk(%{
        type: "content",
        content: chunk
      }))
    end
    
    # Handle based on intent
    {_metadata, response_actions} = case intent do
      :package_search ->
        ResponseHandlers.handle_package_search(content, stream_fn)
      :package_install ->
        ResponseHandlers.handle_package_install(content, stream_fn)
      :agent_create ->
        ResponseHandlers.handle_agent_create(content, stream_fn)
      :pricing_query ->
        ResponseHandlers.handle_pricing_query(stream_fn)
      :general ->
        history = load_conversation_history(user.id, org)
        ResponseHandlers.handle_general(content, history, stream_fn)
      _ ->
        ResponseHandlers.handle_general(content, [], stream_fn)
    end
    
    # Save assistant message
    {:ok, _assistant_message} = Message
      |> Ash.Changeset.for_create(:create, %{
        conversation_id: conversation_id,
        role: :assistant,
        content: accumulated_content,
        intent: intent,
        actions: response_actions || [],
        user_id: user.id
      })
      |> Ash.Changeset.set_tenant(org)
      |> Ash.create()
    
    # Send completion event with actions
    chunk(conn, format_sse_chunk(%{
      type: "complete",
      message_id: message_id,
      actions: response_actions || []
    }))
    
    chunk(conn, "data: [DONE]\n\n")
    
    conn
  end
  
  defp format_sse_chunk(data) do
    "data: #{Jason.encode!(data)}\n\n"
  end
  
  defp load_conversation_history(user_id, org) do
    conversation = Conversation
                   |> Ash.Query.filter(user_id == ^user_id)
                   |> Ash.Query.set_tenant(org)
                   |> Ash.read_one()
    
    case conversation do
      {:ok, conv} ->
        Message
        |> Ash.Query.for_read(:by_conversation, %{conversation_id: conv.id})
        |> Ash.Query.set_tenant(org)
        |> Ash.read!()
      _ ->
        []
    end
  end
  
  defp serialize_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        id: msg.id,
        role: msg.role,
        content: msg.content,
        actions: msg.actions || [],
        inserted_at: msg.inserted_at
      }
    end)
  end
  
  defp serialize_user(user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email
    }
  end
end
```

### Step 6: Add Routes

Update `lib/fleet_prompt_web/router.ex`:

```elixir
scope "/", FleetPromptWeb do
  pipe_through :browser

  get "/", ChatController, :index
  post "/chat/send", ChatController, :send_message
  
  get "/marketplace", MarketplaceController, :index
  get "/marketplace/:slug", MarketplaceController, :show
end
```

### Step 7: Generate Migrations

```bash
mix ash_postgres.generate_migrations --name add_chat_system
mix ecto.migrate
```

## Frontend Implementation (Svelte)

### Step 8: Create Chat Components

Create `assets/src/lib/components/chat/Message.svelte`:

```svelte
<script lang="ts">
  import { marked } from 'marked';
  import { router } from '@inertiajs/svelte';
  import Button from '$lib/components/ui/button/Button.svelte';
  import { User, Bot } from 'lucide-svelte';
  
  interface Action {
    type: string;
    label: string;
    variant?: string;
    package_id?: string;
    package_slug?: string;
    path?: string;
    description?: string;
  }
  
  interface Props {
    message: {
      id: string;
      role: 'user' | 'assistant';
      content: string;
      actions?: Action[];
      inserted_at: string;
    };
  }
  
  let { message }: Props = $props();
  
  let html = $derived(marked(message.content));
  
  function handleAction(action: Action) {
    switch (action.type) {
      case 'view_package':
        router.visit(`/marketplace/${action.package_slug}`);
        break;
      case 'install_package':
        router.post('/packages/install', {
          package_id: action.package_id
        });
        break;
      case 'navigate':
        router.visit(action.path!);
        break;
      case 'start_agent_builder':
        router.visit('/agents/new', {
          data: { description: action.description }
        });
        break;
      case 'start_trial':
        router.visit('/signup?plan=free');
        break;
      default:
        console.log('Unknown action:', action);
    }
  }
</script>

<div class="flex gap-3 items-start {message.role === 'user' ? 'justify-end' : ''}">
  {#if message.role === 'assistant'}
    <div class="w-8 h-8 rounded-full bg-gradient-to-r from-primary to-primary/80 flex items-center justify-center flex-shrink-0">
      <Bot class="w-5 h-5 text-primary-foreground" />
    </div>
  {/if}
  
  <div class="flex-1 {message.role === 'user' ? 'flex justify-end' : ''}">
    {#if message.role === 'assistant'}
      <div class="text-xs text-muted-foreground mb-1">FleetPrompt</div>
    {/if}
    
    <div class={`
      rounded-2xl px-4 py-3 max-w-2xl
      ${message.role === 'user' 
        ? 'bg-primary text-primary-foreground rounded-tr-sm' 
        : 'bg-muted rounded-tl-sm'}
    `}>
      <div class="prose prose-sm max-w-none {message.role === 'user' ? 'prose-invert' : ''}">
        {@html html}
      </div>
      
      {#if message.actions && message.actions.length > 0}
        <div class="mt-4 flex gap-2 flex-wrap">
          {#each message.actions as action}
            <Button
              size="sm"
              variant={action.variant || 'default'}
              onclick={() => handleAction(action)}
            >
              {action.label}
            </Button>
          {/each}
        </div>
      {/if}
    </div>
    
    <div class="text-xs text-muted-foreground mt-1">
      {new Date(message.inserted_at).toLocaleTimeString()}
    </div>
  </div>
  
  {#if message.role === 'user'}
    <div class="w-8 h-8 rounded-full bg-muted flex items-center justify-center flex-shrink-0">
      <User class="w-5 h-5 text-muted-foreground" />
    </div>
  {/if}
</div>
```

Create `assets/src/lib/components/chat/TypingIndicator.svelte`:

```svelte
<script lang="ts">
  import { Bot } from 'lucide-svelte';
</script>

<div class="flex gap-3 items-start">
  <div class="w-8 h-8 rounded-full bg-gradient-to-r from-primary to-primary/80 flex items-center justify-center flex-shrink-0">
    <Bot class="w-5 h-5 text-primary-foreground" />
  </div>
  
  <div class="flex-1">
    <div class="text-xs text-muted-foreground mb-1">FleetPrompt</div>
    <div class="bg-muted rounded-2xl rounded-tl-sm px-4 py-3 inline-block">
      <div class="flex gap-1">
        <span class="w-2 h-2 bg-muted-foreground rounded-full animate-pulse"></span>
        <span class="w-2 h-2 bg-muted-foreground rounded-full animate-pulse" style="animation-delay: 0.2s"></span>
        <span class="w-2 h-2 bg-muted-foreground rounded-full animate-pulse" style="animation-delay: 0.4s"></span>
      </div>
    </div>
  </div>
</div>
```

### Step 9: Create Chat Page

Create `assets/src/pages/Chat/Index.svelte`:

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { router } from '@inertiajs/svelte';
  import Message from '$lib/components/chat/Message.svelte';
  import TypingIndicator from '$lib/components/chat/TypingIndicator.svelte';
  import Button from '$lib/components/ui/button/Button.svelte';
  import { Send, Menu } from 'lucide-svelte';
  
  interface ChatMessage {
    id: string;
    role: 'user' | 'assistant';
    content: string;
    actions?: any[];
    inserted_at: string;
  }
  
  interface Props {
    messages: ChatMessage[];
    user?: {
      id: string;
      name: string;
      email: string;
    };
  }
  
  let { messages: initialMessages, user }: Props = $props();
  
  let messages = $state<ChatMessage[]>(initialMessages);
  let input = $state('');
  let isStreaming = $state(false);
  let streamingMessage = $state<ChatMessage | null>(null);
  let messagesContainer: HTMLDivElement;
  let textarea: HTMLTextAreaElement;
  
  onMount(() => {
    scrollToBottom();
  });
  
  function scrollToBottom() {
    if (messagesContainer) {
      messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
  }
  
  async function sendMessage(e: Event) {
    e.preventDefault();
    
    if (!input.trim() || isStreaming) return;
    
    const userMessage: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'user',
      content: input,
      inserted_at: new Date().toISOString()
    };
    
    messages = [...messages, userMessage];
    input = '';
    
    // Auto-resize textarea
    if (textarea) {
      textarea.style.height = 'auto';
    }
    
    scrollToBottom();
    
    // Start streaming
    isStreaming = true;
    streamingMessage = {
      id: crypto.randomUUID(),
      role: 'assistant',
      content: '',
      actions: [],
      inserted_at: new Date().toISOString()
    };
    
    try {
      const response = await fetch('/chat/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
        },
        body: JSON.stringify({ message: userMessage.content })
      });
      
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      
      if (!reader) throw new Error('No reader');
      
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        
        const chunk = decoder.decode(value);
        const lines = chunk.split('\n\n');
        
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6);
            
            if (data === '[DONE]') {
              // Stream complete
              messages = [...messages, streamingMessage!];
              streamingMessage = null;
              isStreaming = false;
              break;
            }
            
            try {
              const parsed = JSON.parse(data);
              
              if (parsed.type === 'content') {
                streamingMessage!.content += parsed.content;
                scrollToBottom();
              } else if (parsed.type === 'complete') {
                streamingMessage!.actions = parsed.actions || [];
              }
            } catch (e) {
              console.error('Parse error:', e);
            }
          }
        }
      }
    } catch (error) {
      console.error('Error sending message:', error);
      isStreaming = false;
      streamingMessage = null;
    }
  }
  
  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage(e);
    }
  }
  
  function autoResize() {
    if (textarea) {
      textarea.style.height = 'auto';
      textarea.style.height = Math.min(textarea.scrollHeight, 200) + 'px';
    }
  }
</script>

<svelte:head>
  <title>FleetPrompt - Chat</title>
</svelte:head>

<div class="h-screen flex bg-background">
  <!-- Sidebar (optional - mobile hidden) -->
  <aside class="w-64 border-r bg-muted/20 hidden md:flex flex-col">
    <div class="p-4 border-b">
      <h3 class="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
        Quick Actions
      </h3>
    </div>
    
    <nav class="flex-1 p-4 space-y-2">
      <Button
        variant="ghost"
        class="w-full justify-start"
        onclick={() => router.visit('/agents/new')}
      >
        🚀 Deploy Agent
      </Button>
      
      <Button
        variant="ghost"
        class="w-full justify-start"
        onclick={() => router.visit('/marketplace')}
      >
        📦 Browse Packages
      </Button>
      
      <Button
        variant="ghost"
        class="w-full justify-start"
        onclick={() => router.visit('/examples')}
      >
        💡 See Examples
      </Button>
      
      <Button
        variant="ghost"
        class="w-full justify-start"
        onclick={() => router.visit('/dashboard')}
      >
        📊 View Dashboard
      </Button>
    </nav>
    
    <div class="p-4 border-t text-xs text-muted-foreground space-y-1">
      <div class="flex items-center gap-2">
        <div class="w-2 h-2 bg-green-500 rounded-full"></div>
        <span>All systems operational</span>
      </div>
      <div>10,247 agents running</div>
    </div>
  </aside>

  <!-- Chat Area -->
  <main class="flex-1 flex flex-col">
    <!-- Header -->
    <header class="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60 z-10">
      <div class="flex items-center justify-between p-4">
        <div class="flex items-center gap-3">
          <Button variant="ghost" size="icon" class="md:hidden">
            <Menu class="w-5 h-5" />
          </Button>
          <div>
            <h1 class="text-lg font-semibold">FleetPrompt</h1>
            <p class="text-xs text-muted-foreground">Deploy AI agent fleets in minutes</p>
          </div>
        </div>
        
        {#if user}
          <div class="flex items-center gap-2">
            <span class="text-sm text-muted-foreground">{user.name}</span>
          </div>
        {:else}
          <Button onclick={() => router.visit('/login')}>Sign In</Button>
        {/if}
      </div>
    </header>

    <!-- Messages Container -->
    <div 
      bind:this={messagesContainer}
      class="flex-1 overflow-y-auto px-4 py-8"
    >
      <div class="max-w-3xl mx-auto space-y-6">
        {#each messages as message (message.id)}
          <Message {message} />
        {/each}
        
        {#if streamingMessage}
          <Message message={streamingMessage} />
        {/if}
        
        {#if isStreaming && !streamingMessage?.content}
          <TypingIndicator />
        {/if}
      </div>
    </div>

    <!-- Input Area -->
    <div class="border-t bg-background">
      <div class="max-w-3xl mx-auto p-4">
        <form onsubmit={sendMessage} class="relative">
          <textarea
            bind:this={textarea}
            bind:value={input}
            onkeydown={handleKeyDown}
            oninput={autoResize}
            rows="1"
            placeholder="Ask me anything about FleetPrompt..."
            disabled={isStreaming}
            class="w-full resize-none rounded-xl border border-input bg-background px-4 py-3 pr-12 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            style="min-height: 48px; max-height: 200px;"
          ></textarea>
          
          <Button
            type="submit"
            size="icon"
            disabled={!input.trim() || isStreaming}
            class="absolute right-2 bottom-2"
          >
            <Send class="w-4 h-4" />
          </Button>
        </form>
        
        <div class="mt-2 text-xs text-muted-foreground text-center">
          Powered by FleetPrompt AI • 
          <a href="/privacy" class="hover:text-foreground">Privacy</a> • 
          <a href="/terms" class="hover:text-foreground">Terms</a>
        </div>
      </div>
    </div>
  </main>
</div>
```

### Step 10: Install marked for Markdown

```bash
cd assets
npm install marked
cd ..
```

### Step 11: Update app.css for animations

Update `assets/src/app.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  /* ... existing CSS variables ... */
}

@layer utilities {
  .animate-pulse-slow {
    animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }
}
```

## Verification Checklist

- [ ] Chat messages resource created
- [ ] Intent classification working
- [ ] SSE streaming implemented
- [ ] Message history persists
- [ ] Interactive action buttons work
- [ ] Markdown rendering works
- [ ] Auto-scroll to bottom
- [ ] Textarea auto-resize
- [ ] Mobile responsive

## Testing

Test different intents:

```
User: "Show me field service packages"
→ Should list packages with "View Details" buttons

User: "Install field service package"
→ Should show install dialog with pricing

User: "Create a customer support agent"
→ Should start agent builder flow

User: "What's the pricing?"
→ Should show pricing tiers with CTAs
```

## Next Phase

**Phase 4: Agent Execution & Workflows**

---

**Completion Status:** Phase 3 creates chat interface with streaming, completing the conversational UX.
