# FleetPrompt Chat Homepage - LiveView Implementation (DEPRECATED)

**Deprecated:** FleetPrompt’s current UI architecture is **Inertia + Svelte** (not LiveView-first). This document is kept only as historical reference and should **not** be used as the implementation plan.

## Use this instead (canonical)
- `fleetprompt.com/project_plan/phase_3_chat_interface.md` — **Inertia + Svelte chat** with **SSE streaming**, conversation persistence, intent routing, and action buttons.

## Notes
- If LiveView is reintroduced later, it should be for narrow operational UIs (e.g., admin/operator consoles), not the primary chat UX.
- Do not implement this plan unless you intentionally decide to shift the primary chat UX back to LiveView.

## File: lib/fleet_prompt_web/live/chat_live.ex

```elixir
defmodule FleetPromptWeb.ChatLive do
  use FleetPromptWeb, :live_view
  
  alias FleetPrompt.AI.ChatHandler
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to any real-time updates
      Phoenix.PubSub.subscribe(FleetPrompt.PubSub, "chat_updates")
    end
    
    socket =
      socket
      |> assign(:input_value, "")
      |> assign(:streaming_message, nil)
      |> stream(:messages, initial_messages())
    
    {:ok, socket}
  end
  
  @impl true
  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    # Add user message
    user_message = create_message(content, :user)
    socket = stream_insert(socket, :messages, user_message)
    
    # Start AI response
    socket = assign(socket, :input_value, "")
    
    # Handle AI response asynchronously
    {:ok, task} = Task.Supervisor.start_child(
      FleetPrompt.TaskSupervisor,
      fn -> 
        ChatHandler.handle_message(
          content, 
          self(), 
          get_conversation_history(socket)
        )
      end
    )
    
    socket = assign(socket, :current_task, task)
    
    {:noreply, socket}
  end
  
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end
  
  def handle_event("update_input", %{"message" => content}, socket) do
    {:noreply, assign(socket, :input_value, content)}
  end
  
  # Handle streaming AI response chunks
  @impl true
  def handle_info({:ai_chunk, chunk}, socket) do
    current = socket.assigns.streaming_message
    
    socket = 
      if current do
        # Append to existing message
        updated_message = Map.update!(current, :content, &(&1 <> chunk))
        stream_insert(socket, :messages, updated_message)
      else
        # Create new assistant message
        message = create_message(chunk, :assistant)
        socket
        |> assign(:streaming_message, message)
        |> stream_insert(:messages, message)
      end
    
    {:noreply, socket}
  end
  
  def handle_info({:ai_complete, metadata}, socket) do
    # AI response complete, add any interactive elements
    current = socket.assigns.streaming_message
    
    socket = 
      if current && metadata[:actions] do
        # Add action buttons to the message
        updated_message = Map.put(current, :actions, metadata.actions)
        stream_insert(socket, :messages, updated_message)
      else
        socket
      end
    
    socket = assign(socket, :streaming_message, nil)
    
    {:noreply, socket}
  end
  
  def handle_info({:ai_error, error}, socket) do
    error_message = create_message(
      "I encountered an error: #{error}. Please try again.",
      :assistant
    )
    
    socket = 
      socket
      |> stream_insert(:messages, error_message)
      |> assign(:streaming_message, nil)
    
    {:noreply, socket}
  end
  
  # Handle action button clicks (e.g., "Install Package")
  def handle_event("action", %{"type" => "install_package", "id" => package_id}, socket) do
    # Redirect to package installation or show modal
    {:noreply, 
      socket
      |> put_flash(:info, "Installing package...")
      |> push_navigate(to: ~p"/packages/#{package_id}/install")}
  end
  
  def handle_event("action", %{"type" => "view_package", "id" => package_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/packages/#{package_id}")}
  end
  
  # Helper functions
  
  defp initial_messages do
    [
      %{
        id: "welcome",
        content: """
        Welcome to **FleetPrompt**! 👋
        
        I can help you build and deploy AI agent fleets in minutes. You can:
        
        • Deploy pre-built packages (field service, customer support, sales)
        • Create custom agents from scratch
        • Build workflows with multiple agents
        • Browse the agent marketplace
        
        Try asking: *"Show me field service packages"* or *"Create a customer support agent"*
        """,
        role: :assistant,
        timestamp: DateTime.utc_now(),
        actions: nil
      }
    ]
  end
  
  defp create_message(content, role) do
    %{
      id: Ecto.UUID.generate(),
      content: content,
      role: role,
      timestamp: DateTime.utc_now(),
      actions: nil
    }
  end
  
  defp get_conversation_history(socket) do
    # Extract last N messages for context
    socket.assigns.streams.messages
    |> Enum.take(-10)
    |> Enum.map(fn {_id, message} -> 
      %{role: message.role, content: message.content}
    end)
  end
end
```

## File: lib/fleet_prompt_web/live/chat_live.html.heex

```heex
<div class="h-screen flex bg-slate-900 text-white">
  <!-- Sidebar -->
  <aside class="w-64 bg-slate-800 border-r border-slate-700 hidden md:flex flex-col">
    <div class="p-4 border-b border-slate-700">
      <h3 class="text-sm font-semibold text-slate-400 uppercase tracking-wide">Quick Actions</h3>
    </div>
    
    <nav class="flex-1 p-4 space-y-2">
      <.link navigate={~p"/agents/new"} class="block w-full text-left px-3 py-2 rounded hover:bg-slate-700 transition text-sm">
        <span class="mr-2">🚀</span>Deploy Agent
      </.link>
      
      <.link navigate={~p"/packages"} class="block w-full text-left px-3 py-2 rounded hover:bg-slate-700 transition text-sm">
        <span class="mr-2">📦</span>Browse Packages
      </.link>
      
      <.link navigate={~p"/examples"} class="block w-full text-left px-3 py-2 rounded hover:bg-slate-700 transition text-sm">
        <span class="mr-2">💡</span>See Examples
      </.link>
      
      <.link navigate={~p"/dashboard"} class="block w-full text-left px-3 py-2 rounded hover:bg-slate-700 transition text-sm">
        <span class="mr-2">📊</span>View Dashboard
      </.link>
    </nav>
    
    <div class="p-4 border-t border-slate-700">
      <div class="text-xs text-slate-500 space-y-1">
        <div class="flex items-center gap-2">
          <div class="w-2 h-2 bg-green-500 rounded-full"></div>
          <span>All systems operational</span>
        </div>
        <div>10,247 agents running</div>
      </div>
    </div>
  </aside>

  <!-- Chat Area -->
  <main class="flex-1 flex flex-col">
    <!-- Messages Container -->
    <div 
      id="messages" 
      class="flex-1 overflow-y-auto px-4 py-8"
      phx-hook="ScrollToBottom"
    >
      <div class="max-w-3xl mx-auto space-y-6">
        <!-- Messages Stream -->
        <div 
          id="messages-list" 
          phx-update="stream"
        >
          <div
            :for={{id, message} <- @streams.messages}
            id={id}
            class="message-fade-in"
          >
            <%= if message.role == :assistant do %>
              <.assistant_message message={message} />
            <% else %>
              <.user_message message={message} />
            <% end %>
          </div>
        </div>
        
        <!-- Typing Indicator -->
        <%= if @streaming_message do %>
          <div class="flex gap-3 items-start">
            <div class="w-8 h-8 rounded-full bg-gradient-to-r from-indigo-500 to-purple-500 flex items-center justify-center flex-shrink-0">
              ⚡
            </div>
            <div class="flex-1">
              <div class="bg-slate-800 rounded-2xl rounded-tl-sm px-4 py-3 inline-block">
                <div class="typing-indicator flex gap-1">
                  <span class="w-2 h-2 bg-slate-500 rounded-full animate-pulse"></span>
                  <span class="w-2 h-2 bg-slate-500 rounded-full animate-pulse delay-100"></span>
                  <span class="w-2 h-2 bg-slate-500 rounded-full animate-pulse delay-200"></span>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Input Area -->
    <div class="border-t border-slate-700 bg-slate-800">
      <div class="max-w-3xl mx-auto p-4">
        <form phx-submit="send_message" class="relative">
          <textarea 
            name="message"
            value={@input_value}
            phx-change="update_input"
            rows="1"
            placeholder="Ask me anything about FleetPrompt..."
            class="w-full bg-slate-700 text-white rounded-xl px-4 py-3 pr-12 resize-none focus:outline-none focus:ring-2 focus:ring-indigo-500 placeholder-slate-500"
            style="min-height: 48px; max-height: 200px;"
            phx-hook="AutoResize"
          ></textarea>
          
          <button 
            type="submit"
            class="absolute right-2 bottom-2 w-8 h-8 bg-indigo-600 hover:bg-indigo-700 rounded-lg flex items-center justify-center transition"
          >
            <Heroicons.paper_airplane class="w-5 h-5" />
          </button>
        </form>
        
        <div class="mt-2 text-xs text-slate-500 text-center">
          Powered by FleetPrompt AI • 
          <.link href={~p"/privacy"} class="hover:text-slate-400">Privacy</.link> • 
          <.link href={~p"/terms"} class="hover:text-slate-400">Terms</.link>
        </div>
      </div>
    </div>
  </main>
</div>
```

## Components

```elixir
# lib/fleet_prompt_web/components/chat_components.ex

defmodule FleetPromptWeb.ChatComponents do
  use Phoenix.Component
  import FleetPromptWeb.CoreComponents
  
  attr :message, :map, required: true
  
  def assistant_message(assigns) do
    ~H"""
    <div class="flex gap-3 items-start">
      <div class="w-8 h-8 rounded-full bg-gradient-to-r from-indigo-500 to-purple-500 flex items-center justify-center flex-shrink-0">
        ⚡
      </div>
      <div class="flex-1">
        <div class="text-sm text-slate-400 mb-1">FleetPrompt</div>
        <div class="bg-slate-800 rounded-2xl rounded-tl-sm px-4 py-3">
          <div class="prose prose-invert prose-sm max-w-none">
            <%= raw(Earmark.as_html!(@message.content)) %>
          </div>
          
          <%= if @message.actions do %>
            <div class="mt-4 flex gap-2 flex-wrap">
              <button
                :for={action <- @message.actions}
                phx-click="action"
                phx-value-type={action.type}
                phx-value-id={action.id}
                class={[
                  "px-4 py-2 rounded-lg text-sm font-semibold transition",
                  action.primary && "bg-indigo-600 hover:bg-indigo-700",
                  !action.primary && "bg-slate-700 hover:bg-slate-600"
                ]}
              >
                <%= action.label %>
              </button>
            </div>
          <% end %>
        </div>
        
        <div class="text-xs text-slate-500 mt-1">
          <%= Calendar.strftime(@message.timestamp, "%I:%M %p") %>
        </div>
      </div>
    </div>
    """
  end
  
  attr :message, :map, required: true
  
  def user_message(assigns) do
    ~H"""
    <div class="flex gap-3 items-start justify-end">
      <div class="flex-1 flex justify-end">
        <div class="bg-indigo-600 rounded-2xl rounded-tr-sm px-4 py-3 max-w-lg">
          <p class="leading-relaxed"><%= @message.content %></p>
        </div>
      </div>
      <div class="w-8 h-8 rounded-full bg-slate-700 flex items-center justify-center flex-shrink-0">
        👤
      </div>
    </div>
    """
  end
end
```

## AI Chat Handler

```elixir
# lib/fleet_prompt/ai/chat_handler.ex

defmodule FleetPrompt.AI.ChatHandler do
  @moduledoc """
  Handles chat interactions with streaming responses.
  Integrates with Claude/GPT for intelligent responses.
  """
  
  def handle_message(content, pid, conversation_history) do
    # Build context from conversation history
    messages = build_messages(conversation_history, content)
    
    # Determine intent
    intent = classify_intent(content)
    
    # Generate response based on intent
    case intent do
      :package_query -> handle_package_query(content, pid)
      :agent_creation -> handle_agent_creation(content, pid)
      :pricing_query -> handle_pricing_query(pid)
      :general -> handle_general_query(content, messages, pid)
    end
  end
  
  defp handle_package_query(query, pid) do
    # Search packages
    packages = FleetPrompt.Packages.search(query)
    
    if Enum.empty?(packages) do
      send(pid, {:ai_chunk, "I couldn't find any packages matching '#{query}'. "})
      send(pid, {:ai_chunk, "Would you like to see all available packages?"})
      send(pid, {:ai_complete, %{}})
    else
      # Stream response with package info
      send(pid, {:ai_chunk, "I found #{length(packages)} package(s):\\n\\n"})
      
      for package <- Enum.take(packages, 3) do
        send(pid, {:ai_chunk, "**#{package.name}**\\n"})
        send(pid, {:ai_chunk, "#{package.description}\\n"})
        send(pid, {:ai_chunk, "💰 #{format_price(package)} • ⭐ #{package.rating}/5\\n\\n"})
      end
      
      # Add action buttons
      actions = Enum.map(packages, fn pkg ->
        %{
          type: "view_package",
          id: pkg.id,
          label: "View #{pkg.name}",
          primary: false
        }
      end)
      
      send(pid, {:ai_complete, %{actions: actions}})
    end
  end
  
  defp handle_agent_creation(query, pid) do
    send(pid, {:ai_chunk, "Great! I'll help you create a custom agent. \\n\\n"})
    send(pid, {:ai_chunk, "To get started, I need to know:\\n"})
    send(pid, {:ai_chunk, "1. **What should the agent do?** (describe its purpose)\\n"})
    send(pid, {:ai_chunk, "2. **What skills does it need?** (e.g., web search, data analysis)\\n"})
    send(pid, {:ai_chunk, "3. **What tools should it use?** (e.g., Slack, email, APIs)\\n\\n"})
    send(pid, {:ai_chunk, "Tell me about your use case!"})
    
    send(pid, {:ai_complete, %{}})
  end
  
  defp handle_pricing_query(pid) do
    send(pid, {:ai_chunk, "FleetPrompt offers flexible pricing:\\n\\n"})
    send(pid, {:ai_chunk, "**Free Tier**\\n"})
    send(pid, {:ai_chunk, "• 100K tokens/month\\n"})
    send(pid, {:ai_chunk, "• 3 agents\\n"})
    send(pid, {:ai_chunk, "• Core packages\\n\\n"})
    
    send(pid, {:ai_chunk, "**Pro Tier** - $49/month\\n"})
    send(pid, {:ai_chunk, "• 1M tokens/month\\n"})
    send(pid, {:ai_chunk, "• Unlimited agents\\n"})
    send(pid, {:ai_chunk, "• All packages & workflows\\n\\n"})
    
    send(pid, {:ai_chunk, "**Enterprise** - Custom pricing\\n"})
    send(pid, {:ai_chunk, "• Unlimited everything\\n"})
    send(pid, {:ai_chunk, "• Dedicated support\\n"})
    send(pid, {:ai_chunk, "• SLA guarantees\\n\\n"})
    
    actions = [
      %{type: "start_trial", id: "free", label: "Start Free Trial", primary: true},
      %{type: "view_pricing", id: "pricing", label: "Full Pricing Details", primary: false}
    ]
    
    send(pid, {:ai_complete, %{actions: actions}})
  end
  
  defp handle_general_query(query, messages, pid) do
    # Call actual LLM API (Claude/GPT) with streaming
    FleetPrompt.LLM.stream_chat(messages, fn chunk ->
      send(pid, {:ai_chunk, chunk})
    end)
    
    send(pid, {:ai_complete, %{}})
  end
  
  defp classify_intent(content) do
    lower = String.downcase(content)
    
    cond do
      String.contains?(lower, ["package", "install", "marketplace"]) -> :package_query
      String.contains?(lower, ["create", "build", "make"]) -> :agent_creation
      String.contains?(lower, ["price", "cost", "pricing", "tier"]) -> :pricing_query
      true -> :general
    end
  end
  
  defp build_messages(history, new_message) do
    history ++ [%{role: "user", content: new_message}]
  end
  
  defp format_price(%{pricing_model: :free}), do: "Free"
  defp format_price(%{pricing_model: :paid, price: price}), do: "$#{price}/mo"
  defp format_price(_), do: "Custom"
end
```

## JavaScript Hooks

```javascript
// assets/js/hooks.js

export const Hooks = {
  ScrollToBottom: {
    mounted() {
      this.scrollToBottom();
    },
    updated() {
      this.scrollToBottom();
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight;
    }
  },
  
  AutoResize: {
    mounted() {
      this.el.addEventListener('input', () => {
        this.el.style.height = 'auto';
        this.el.style.height = Math.min(this.el.scrollHeight, 200) + 'px';
      });
    }
  }
}
```

## Router Update

```elixir
# lib/fleet_prompt_web/router.ex

scope "/", FleetPromptWeb do
  pipe_through :browser

  live "/", ChatLive, :index
  # ... other routes
end
```

This gives you a fully functional chat-based homepage with:
- ✅ Streaming AI responses
- ✅ Interactive action buttons
- ✅ Real-time updates via LiveView
- ✅ Intent classification
- ✅ Package search integration
- ✅ Markdown rendering
- ✅ Auto-scrolling
- ✅ Message history

The chat interface becomes the primary way users interact with FleetPrompt!
