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

  require Logger

  alias FleetPrompt.Forums.{Category, Post, Thread}
  alias FleetPrompt.Signals.SignalBus

  @doc false
  defp render_page(conn, component, props) when is_map(props) do
    FleetPromptWeb.InertiaHelpers.render_inertia(conn, component, props)
  end

  # GET /forums
  def index(conn, _params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]

    categories =
      cond do
        is_nil(user) ->
          []

        not is_binary(tenant) or String.trim(tenant) == "" ->
          []

        not Code.ensure_loaded?(Category) ->
          []

        true ->
          query =
            Category
            |> Ash.Query.for_read(:read)
            |> Ash.Query.sort(name: :asc)

          case Ash.read(query, tenant: tenant) do
            {:ok, cats} when is_list(cats) ->
              Enum.map(cats, &serialize_category/1)

            {:error, err} ->
              Logger.warning("[Forums] failed to load categories",
                tenant: tenant,
                error: inspect(err)
              )

              []
          end
      end

    render_page(conn, "Forums", %{
      title: "Forums",
      subtitle: "Tenant-scoped discussions (Phase 2C lighthouse).",
      categories: categories,
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

  # GET /forums/categories/new
  def new_category(conn, _params) do
    render_page(conn, "ForumsCategoryNew", %{
      title: "New category",
      subtitle: "Create a forum category for your organization (Phase 2C lighthouse).",
      forum: %{
        view: "category_new"
      }
    })
  end

  # POST /forums/categories
  #
  # Expects JSON (or form) params:
  # - name (required)
  # - slug (required)
  # - description (optional)
  # - status (optional; "active" | "archived")
  #
  # Response: JSON with `{ok, redirect_to, category}`.
  def create_category(conn, params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    role = conn.assigns[:current_role]

    name = params["name"]
    slug = params["slug"]
    description = params["description"]
    status = parse_category_status(params["status"])

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      not Code.ensure_loaded?(Category) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "forums categories are not implemented yet"})

      not can_manage_categories?(role) ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "insufficient permissions to create categories"})

      true ->
        attrs = %{
          name: name,
          slug: slug,
          description: description,
          status: status
        }

        changeset =
          Category
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.Changeset.set_tenant(tenant)

        case Ash.create(changeset) do
          {:ok, %Category{} = category} ->
            actor = %{type: "user", id: to_string(user.id)}
            subject = %{type: "forum.category", id: to_string(category.id)}
            dedupe_key = "forum.category.created:#{tenant}:#{category.slug}"

            payload = %{
              category_id: category.id,
              slug: category.slug,
              name: category.name,
              status: to_string(category.status)
            }

            request_id = request_id_from_logger_or_assigns(conn)

            metadata =
              %{
                request_id: request_id,
                actor_role: (role && to_string(role)) || nil
              }
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            _ =
              SignalBus.emit(
                tenant,
                "forum.category.created",
                payload,
                metadata,
                dedupe_key: dedupe_key,
                actor: actor,
                subject: subject,
                source: "web"
              )

            json(conn, %{
              ok: true,
              redirect_to: "/forums/c/#{category.slug}",
              category: serialize_category(category)
            })

          {:error, err} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              ok: false,
              error: "failed to create category",
              details: inspect(err)
            })
        end
    end
  end

  # GET /forums/c/:slug
  def category(conn, %{"slug" => slug}) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        render_page(conn, "ForumsCategory", %{
          title: "Forums",
          subtitle: "Category",
          category: %{
            id: "cat_#{slug}",
            slug: slug,
            name: slug,
            description: "Sign in to view this category.",
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

      not is_binary(tenant) or String.trim(tenant) == "" ->
        render_page(conn, "ForumsCategory", %{
          title: "Forums",
          subtitle: "Category",
          category: %{
            id: "cat_#{slug}",
            slug: slug,
            name: slug,
            description: "Tenant context is missing. Select an org/tenant and try again.",
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

      not Code.ensure_loaded?(Category) ->
        render_page(conn, "ForumsCategory", %{
          title: "Forums",
          subtitle: "Category",
          category: %{
            id: "cat_#{slug}",
            slug: slug,
            name: slug,
            description: "Forum categories are not implemented yet.",
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

      true ->
        slug = to_string(slug || "") |> String.trim()

        query =
          Category
          |> Ash.Query.for_read(:by_slug, %{slug: slug})

        case Ash.read_one(query, tenant: tenant) do
          {:ok, %Category{} = category} ->
            render_page(conn, "ForumsCategory", %{
              title: "Forums",
              subtitle: "Category",
              category:
                serialize_category_for_category_page(category, %{
                  threads: 0,
                  posts: 0,
                  last_activity_at: nil
                }),
              threads: [],
              forum: %{
                view: "category",
                category_slug: slug
              }
            })

          {:ok, nil} ->
            conn
            |> put_status(:not_found)
            |> render_page("ForumsCategory", %{
              title: "Forums",
              subtitle: "Category not found",
              category: %{
                id: "cat_#{slug}",
                slug: slug,
                name: slug,
                description: "Category not found.",
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

          {:error, err} ->
            Logger.warning("[Forums] failed to load category by slug",
              tenant: tenant,
              slug: slug,
              error: inspect(err)
            )

            conn
            |> put_status(:internal_server_error)
            |> render_page("ForumsCategory", %{
              title: "Forums",
              subtitle: "Category",
              category: %{
                id: "cat_#{slug}",
                slug: slug,
                name: slug,
                description: "Failed to load category.",
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
    end
  end

  # GET /forums/t/:id
  def thread(conn, %{"id" => id}) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    role = conn.assigns[:current_role]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> render_page("ForumsThread", %{
          title: "Forums",
          subtitle: "Thread",
          thread: %{
            id: id,
            title: "Sign in to view this thread.",
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

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> render_page("ForumsThread", %{
          title: "Forums",
          subtitle: "Thread",
          thread: %{
            id: id,
            title: "Tenant context is missing. Select an org/tenant and try again.",
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

      not Code.ensure_loaded?(Thread) or not Code.ensure_loaded?(Post) ->
        conn
        |> put_status(:not_implemented)
        |> render_page("ForumsThread", %{
          title: "Forums",
          subtitle: "Thread",
          thread: %{
            id: id,
            title: "Forums are not fully implemented yet.",
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

      true ->
        query =
          Thread
          |> Ash.Query.for_read(:by_id, %{id: id})

        case Ash.read_one(query, tenant: tenant) do
          {:ok, %Thread{} = thr} ->
            posts_query =
              Post
              |> Ash.Query.for_read(:by_thread, %{thread_id: thr.id})
              |> Ash.Query.sort(inserted_at: :asc)

            posts =
              case Ash.read(posts_query, tenant: tenant) do
                {:ok, ps} when is_list(ps) -> Enum.map(ps, &serialize_post/1)
                {:error, _err} -> []
              end

            can_moderate = role in [:owner, :admin]
            can_reply = thr.status == :open

            render_page(conn, "ForumsThread", %{
              title: "Forums",
              subtitle: "Thread",
              thread: serialize_thread(thr),
              posts: posts,
              can_reply: can_reply,
              can_moderate: can_moderate,
              forum: %{
                view: "thread",
                thread_id: to_string(thr.id)
              }
            })

          {:ok, nil} ->
            conn
            |> put_status(:not_found)
            |> render_page("ForumsThread", %{
              title: "Forums",
              subtitle: "Thread not found",
              thread: %{
                id: id,
                title: "Thread not found.",
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

          {:error, err} ->
            Logger.warning("[Forums] failed to load thread by id",
              tenant: tenant,
              thread_id: id,
              error: inspect(err)
            )

            conn
            |> put_status(:internal_server_error)
            |> render_page("ForumsThread", %{
              title: "Forums",
              subtitle: "Thread",
              thread: %{
                id: id,
                title: "Failed to load thread.",
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
  end

  # POST /forums/threads
  #
  # Expects JSON (or form) params:
  # - category_id (required)
  # - title (required)
  # - body (required) -> creates the first post
  #
  # Response: JSON with `{ok, redirect_to, thread}`.
  def create_thread(conn, params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]

    category_id = params["category_id"]
    title = params["title"] || params["subject"]
    body = params["body"] || params["content"]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      not (is_binary(category_id) and String.trim(category_id) != "") ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "missing required param: category_id"})

      not (is_binary(title) and String.trim(title) != "") ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "missing required param: title"})

      not (is_binary(body) and String.trim(body) != "") ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "missing required param: body"})

      true ->
        thread_changeset =
          Thread
          |> Ash.Changeset.for_create(:create, %{
            category_id: category_id,
            title: title,
            status: :open,
            created_by_user_id: user.id
          })
          |> Ash.Changeset.set_tenant(tenant)

        with {:ok, %Thread{} = thr} <- Ash.create(thread_changeset) do
          post_changeset =
            Post
            |> Ash.Changeset.for_create(:create, %{
              thread_id: thr.id,
              content: body,
              author_type: :human,
              author_id: to_string(user.id),
              metadata: %{
                "source" => "web"
              }
            })
            |> Ash.Changeset.set_tenant(tenant)

          post_result = Ash.create(post_changeset)

          actor = %{type: "user", id: to_string(user.id)}
          request_id = request_id_from_logger_or_assigns(conn)

          _ =
            SignalBus.emit(
              tenant,
              "forum.thread.created",
              %{
                thread_id: thr.id,
                category_id: thr.category_id,
                title: thr.title,
                status: to_string(thr.status)
              },
              %{
                request_id: request_id
              },
              dedupe_key: "forum.thread.created:#{tenant}:#{thr.id}",
              actor: actor,
              subject: %{type: "forum.thread", id: to_string(thr.id)},
              source: "web"
            )

          case post_result do
            {:ok, %Post{} = p} ->
              _ =
                SignalBus.emit(
                  tenant,
                  "forum.post.created",
                  %{
                    post_id: p.id,
                    thread_id: p.thread_id,
                    status: to_string(p.status),
                    author_type: to_string(p.author_type),
                    author_id: p.author_id
                  },
                  %{
                    request_id: request_id
                  },
                  dedupe_key: "forum.post.created:#{tenant}:#{p.id}",
                  actor: actor,
                  subject: %{type: "forum.post", id: to_string(p.id)},
                  source: "web"
                )

              json(conn, %{
                ok: true,
                redirect_to: "/forums/t/#{thr.id}",
                thread: serialize_thread(thr)
              })

            {:error, err} ->
              Logger.warning("[Forums] thread created but failed to create first post",
                tenant: tenant,
                thread_id: thr.id,
                error: inspect(err)
              )

              conn
              |> put_status(:unprocessable_entity)
              |> json(%{
                ok: false,
                error: "thread_created_but_post_failed",
                thread_id: thr.id,
                details: inspect(err)
              })
          end
        else
          {:error, err} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{ok: false, error: "failed to create thread", details: inspect(err)})
        end
    end
  end

  # POST /forums/t/:id/replies
  #
  # Expects JSON (or form) params:
  # - body (required) OR content (required)
  #
  # Response: JSON with `{ok, post}`.
  def create_reply(conn, %{"id" => thread_id} = params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]

    body = params["body"] || params["content"]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      not (is_binary(body) and String.trim(body) != "") ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "missing required param: body"})

      true ->
        changeset =
          Post
          |> Ash.Changeset.for_create(:create, %{
            thread_id: thread_id,
            content: body,
            author_type: :human,
            author_id: to_string(user.id),
            metadata: %{
              "source" => "web"
            }
          })
          |> Ash.Changeset.set_tenant(tenant)

        case Ash.create(changeset) do
          {:ok, %Post{} = post} ->
            actor = %{type: "user", id: to_string(user.id)}
            request_id = request_id_from_logger_or_assigns(conn)

            _ =
              SignalBus.emit(
                tenant,
                "forum.post.created",
                %{
                  post_id: post.id,
                  thread_id: post.thread_id,
                  status: to_string(post.status),
                  author_type: to_string(post.author_type),
                  author_id: post.author_id
                },
                %{
                  request_id: request_id
                },
                dedupe_key: "forum.post.created:#{tenant}:#{post.id}",
                actor: actor,
                subject: %{type: "forum.post", id: to_string(post.id)},
                source: "web"
              )

            json(conn, %{ok: true, post: serialize_post(post)})

          {:error, err} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{ok: false, error: "failed to create reply", details: inspect(err)})
        end
    end
  end

  # -----------------------
  # Serialization / helpers
  # -----------------------

  defp serialize_category(%Category{} = category) do
    %{
      id: category.id,
      slug: category.slug,
      name: category.name,
      description: Map.get(category, :description),
      status: category.status,
      inserted_at: Map.get(category, :inserted_at),
      updated_at: Map.get(category, :updated_at)
    }
  end

  defp serialize_category_for_category_page(%Category{} = category, stats) when is_map(stats) do
    %{
      id: category.id,
      slug: category.slug,
      name: category.name,
      description: Map.get(category, :description),
      is_locked: category.status == :archived,
      stats: %{
        threads: Map.get(stats, :threads),
        posts: Map.get(stats, :posts),
        last_activity_at: Map.get(stats, :last_activity_at)
      }
    }
  end

  defp request_id_from_logger_or_assigns(conn) do
    case Logger.metadata()[:request_id] do
      nil -> Map.get(conn.assigns, :request_id)
      rid -> to_string(rid)
    end
  end

  defp can_manage_categories?(role) when role in [:owner, :admin], do: true
  defp can_manage_categories?(_role), do: false

  defp parse_category_status(nil), do: :active

  defp parse_category_status(v) when is_binary(v) do
    case v |> String.trim() |> String.downcase() do
      "archived" -> :archived
      "active" -> :active
      "" -> :active
      _ -> :active
    end
  end

  defp parse_category_status(_), do: :active

  defp serialize_thread(%Thread{} = thread) do
    %{
      id: thread.id,
      title: thread.title,
      # Category is wired later (we currently store category_id in the thread).
      category: nil,
      status: thread.status,
      created_at: Map.get(thread, :inserted_at),
      updated_at: Map.get(thread, :updated_at),
      author: %{
        id: Map.get(thread, :created_by_user_id),
        name: nil
      },
      tags: []
    }
  end

  defp serialize_post(%Post{} = post) do
    %{
      id: post.id,
      role: to_string(post.author_type),
      author: %{
        id: post.author_id,
        name: nil,
        kind: to_string(post.author_type)
      },
      created_at: Map.get(post, :inserted_at),
      body: post.content,
      reactions: %{}
    }
  end
end
