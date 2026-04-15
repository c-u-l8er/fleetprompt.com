defmodule FleetPromptWeb.CoreComponents do
  @moduledoc """
  Shared UI components for FleetPrompt LiveView pages.
  """

  use Phoenix.Component

  alias FleetPrompt.Trust.Engine

  @doc """
  Renders a trust score badge with color coding.

  ## Examples

      <.trust_badge score={87} />
      <.trust_badge score={nil} />
  """
  attr :score, :integer, default: nil

  def trust_badge(assigns) do
    display =
      if assigns.score, do: Engine.display(assigns.score), else: %{label: "N/A", color: "gray"}

    assigns = assign(assigns, :display, display)

    ~H"""
    <span class={"trust-badge trust-#{@display.color}"}>
      <span class="trust-score">{@score || "—"}</span>
      <span class="trust-label">{@display.label}</span>
    </span>
    """
  end

  @doc """
  Renders a status pill for manifest lifecycle state.
  """
  attr :status, :atom, required: true

  def status_pill(assigns) do
    ~H"""
    <span class={"status-pill status-#{@status}"}>{@status}</span>
    """
  end

  @doc """
  Renders a permission badge showing declared agent capabilities.
  """
  attr :permission, :map, required: true

  def permission_badge(assigns) do
    ~H"""
    <div class="permission-badge">
      <span class="permission-capability">{@permission["capability"]}</span>
      <span class="permission-scope">{@permission["scope"]}</span>
      <span :if={@permission["reason"]} class="permission-reason">{@permission["reason"]}</span>
    </div>
    """
  end

  @doc """
  Renders a search input with keyboard shortcut hint.
  """
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "Search agents..."

  def search_input(assigns) do
    ~H"""
    <div class="search-container">
      <input
        type="text"
        name="q"
        value={@value}
        placeholder={@placeholder}
        phx-debounce="300"
        class="search-input"
        autofocus
      />
      <kbd class="search-shortcut">⌘K</kbd>
    </div>
    """
  end
end
