defmodule FleetPromptWeb.ForumsController do
  @moduledoc """
  Forum UX scaffolding (Phase 6 target), rendered via Inertia.

  This controller intentionally ships *before* Phase 6 so you can wire navigation
  and URLs without committing to the full forum data model yet.

  Current behavior (foundation / mocked):
  - Renders Inertia pages that already exist in the frontend:
    - `Forums` (index)
    - `ForumsCategory` (category view)
    - `ForumsThread` (thread view)
    - `ForumsNew` (new thread form)

  Upgrade path:
  - Replace the mocked props here with real Phase 6 Ash reads/writes.
  - Mutations should become directive-backed, with signals emitted for auditability.
  """

  use FleetPromptWeb, :controller

  @doc false
  defp render_page(conn, component, props) when is_map(props) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, component, props)
  end

  # GET /forums
  def index(conn, _params) do
    render_page(conn, "Forums", %{
      title: "Forums",
      subtitle: "Agent-native discussions (mocked UI). Ready for Phase 6 wiring.",
      forum: %{
        view: "index"
      }
    })
  end

  # GET /forums/new
  def new(conn, _params) do
    render_page(conn, "ForumsNew", %{
      title: "New thread",
      subtitle: "Start a discussion. (Forums are mocked for now — wiring will land in Phase 6.)",
      forum: %{
        view: "new"
      }
    })
  end

  # GET /forums/c/:slug
  def category(conn, %{"slug" => slug}) do
    render_page(conn, "ForumsCategory", %{
      title: "Forums",
      subtitle: "Category",
      category: %{
        id: "cat_#{slug}",
        slug: slug,
        name:
          String.replace(slug, "-", " ")
          |> String.split()
          |> Enum.map_join(" ", &String.capitalize/1),
        description: "Category view (mocked). Phase 6 will wire real resources.",
        is_locked: false,
        stats: %{
          threads: 0,
          posts: 0,
          last_activity_at: nil
        }
      },
      threads: [],
      forum: %{
        view: "category",
        category_slug: slug
      }
    })
  end

  # GET /forums/t/:id
  def thread(conn, %{"id" => id}) do
    render_page(conn, "ForumsThread", %{
      title: "Forums",
      subtitle: "Thread",
      thread: %{
        id: id,
        title: "Thread #{id} (mocked)",
        category: nil,
        status: "open",
        created_at: nil,
        updated_at: nil,
        author: nil,
        tags: []
      },
      posts: [],
      can_reply: false,
      can_moderate: false,
      forum: %{
        view: "thread",
        thread_id: id
      }
    })
  end
end
