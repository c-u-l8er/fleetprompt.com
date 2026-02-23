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
  require Ash.Query

  alias FleetPrompt.Directives.Directive
  alias FleetPrompt.Forums.{Category, Post, Thread}
  alias FleetPrompt.Jobs.DirectiveRunner
  alias FleetPrompt.Signals.{Signal, SignalBus}

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
              Logger.warning("[Forums] failed to load categories for new thread page",
                tenant: tenant,
                error: inspect(err)
              )

              []
          end
      end

    render_page(conn, "ForumsNew", %{
      title: "New thread",
      subtitle: "Start a discussion (Phase 2C lighthouse).",
      categories: categories,
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
            threads_raw =
              cond do
                not Code.ensure_loaded?(Thread) ->
                  []

                true ->
                  threads_query =
                    Thread
                    |> Ash.Query.for_read(:by_category, %{category_id: category.id})

                  case Ash.read(threads_query, tenant: tenant) do
                    {:ok, thrs} when is_list(thrs) ->
                      thrs

                    {:error, err} ->
                      Logger.warning("[Forums] failed to load category threads",
                        tenant: tenant,
                        category_id: category.id,
                        error: inspect(err)
                      )

                      []

                    _ ->
                      []
                  end
              end

            {threads, threads_count, posts_count, last_activity_at} =
              threads_raw
              |> Enum.reduce({[], 0, 0, nil}, fn thr, {acc, tcount, pcount, last} ->
                posts_for_thread =
                  if Code.ensure_loaded?(Post) do
                    posts_q =
                      Post
                      |> Ash.Query.for_read(:by_thread, %{thread_id: thr.id})

                    case Ash.read(posts_q, tenant: tenant) do
                      {:ok, ps} when is_list(ps) -> ps
                      _ -> []
                    end
                  else
                    []
                  end

                post_count = length(posts_for_thread)
                replies = max(post_count - 1, 0)

                updated_at = Map.get(thr, :updated_at) || Map.get(thr, :inserted_at)

                # Prefer post activity when available, otherwise fall back to thread timestamps.
                post_last_activity =
                  posts_for_thread
                  |> Enum.map(fn p -> Map.get(p, :updated_at) || Map.get(p, :inserted_at) end)
                  |> Enum.reduce(nil, fn dt, acc -> max_datetime(acc, dt) end)

                last =
                  last
                  |> max_datetime(updated_at)
                  |> max_datetime(post_last_activity)

                serialized_thread = %{
                  id: thr.id,
                  title: thr.title,
                  excerpt: nil,
                  is_pinned: false,
                  is_locked: thr.status == :locked,
                  tags: [],
                  created_at:
                    case Map.get(thr, :inserted_at) do
                      %DateTime{} = dt ->
                        DateTime.to_iso8601(dt)

                      %NaiveDateTime{} = ndt ->
                        ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

                      _ ->
                        nil
                    end,
                  updated_at:
                    case Map.get(thr, :updated_at) do
                      %DateTime{} = dt ->
                        DateTime.to_iso8601(dt)

                      %NaiveDateTime{} = ndt ->
                        ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

                      _ ->
                        nil
                    end,
                  author: %{
                    id: Map.get(thr, :created_by_user_id),
                    name: nil
                  },
                  stats: %{
                    replies: replies,
                    views: 0,
                    reactions: 0
                  }
                }

                {[serialized_thread | acc], tcount + 1, pcount + post_count, last}
              end)

            threads = Enum.reverse(threads)

            render_page(conn, "ForumsCategory", %{
              title: "Forums",
              subtitle: "Category",
              category:
                serialize_category_for_category_page(category, %{
                  threads: threads_count,
                  posts: posts_count,
                  last_activity_at: last_activity_at
                }),
              threads: threads,
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

            audit_signals = load_thread_audit_signals(tenant, thr.id)
            audit_directives = load_thread_audit_directives(tenant, thr.id)

            audit_events =
              Enum.concat([
                Enum.map(audit_signals, &Map.put(&1, :kind, "signal")),
                Enum.map(audit_directives, &Map.put(&1, :kind, "directive"))
              ])

            render_page(conn, "ForumsThread", %{
              title: "Forums",
              subtitle: "Thread",
              thread: serialize_thread(thr),
              posts: posts,
              can_reply: can_reply,
              can_moderate: can_moderate,
              audit_events: audit_events,
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

      not category_exists?(tenant, category_id) ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "category_not_found"})

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
        case get_thread_by_id(tenant, thread_id) do
          {:ok, nil} ->
            conn
            |> put_status(:not_found)
            |> json(%{ok: false, error: "thread_not_found"})

          {:ok, %Thread{} = thr} ->
            if thr.status != :open do
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{ok: false, error: "thread_not_open"})
            else
              changeset =
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

          {:error, err} ->
            Logger.warning("[Forums] failed to load thread before creating reply",
              tenant: tenant,
              thread_id: thread_id,
              error: inspect(err)
            )

            conn
            |> put_status(:internal_server_error)
            |> json(%{ok: false, error: "failed_to_load_thread"})
        end
    end
  end

  # -----------------------
  # Forums moderation (Phase 2C lighthouse)
  # -----------------------
  #
  # These endpoints are intentionally directive-backed:
  # - the controller records auditable intent (Directive + "directive.requested" signal)
  # - the runner performs the mutation and emits lifecycle + domain signals
  #
  # NOTE: Authorization is enforced here (request-time). The DirectiveRunner does not authorize.
  def lock_thread(conn, %{"id" => thread_id} = _params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    role = conn.assigns[:current_role]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      role not in [:owner, :admin] ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "insufficient permissions"})

      not Code.ensure_loaded?(Directive) or not Code.ensure_loaded?(DirectiveRunner) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "directives are not implemented yet"})

      true ->
        case get_thread_by_id(tenant, thread_id) do
          {:ok, nil} ->
            conn
            |> put_status(:not_found)
            |> json(%{ok: false, error: "thread_not_found"})

          {:ok, %Thread{} = thr} ->
            idempotency_key = "forum.thread.lock:#{tenant}:#{thr.id}"

            subject = %{type: "forum.thread", id: to_string(thr.id)}
            actor = %{type: "user", id: to_string(user.id)}

            request_id = request_id_from_logger_or_assigns(conn)

            payload = %{
              "thread_id" => to_string(thr.id),
              "subject" => %{"type" => "forum.thread", "id" => to_string(thr.id)}
            }

            metadata =
              %{
                "request_id" => request_id,
                "actor_role" => (role && to_string(role)) || nil,
                "source" => "web"
              }
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            with {:ok, %Directive{} = directive, directive_marker} <-
                   get_or_create_directive(
                     tenant,
                     %{
                       name: "forum.thread.lock",
                       idempotency_key: idempotency_key,
                       requested_by_user_id: user.id,
                       payload: payload,
                       metadata: metadata
                     },
                     idempotency_key
                   ),
                 :ok <-
                   emit_directive_requested_signal(
                     tenant,
                     directive,
                     actor,
                     subject,
                     %{
                       "thread_id" => to_string(thr.id),
                       "directive_created" => directive_marker == :created
                     }
                   ),
                 {:ok, enqueued?} <- enqueue_directive_runner_job(directive, tenant) do
              json(conn, %{
                ok: true,
                tenant: tenant,
                directive_id: directive.id,
                directive_status: directive.status,
                directive_created: directive_marker == :created,
                enqueued: enqueued?,
                thread_id: thr.id
              })
            else
              {:error, err} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{ok: false, error: normalize_error(err)})

              {:discard, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{ok: false, error: reason})
            end

          {:error, err} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{ok: false, error: normalize_error(err)})
        end
    end
  end

  def unlock_thread(conn, %{"id" => thread_id} = _params) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    role = conn.assigns[:current_role]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      role not in [:owner, :admin] ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "insufficient permissions"})

      not Code.ensure_loaded?(Directive) or not Code.ensure_loaded?(DirectiveRunner) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "directives are not implemented yet"})

      true ->
        case get_thread_by_id(tenant, thread_id) do
          {:ok, nil} ->
            conn
            |> put_status(:not_found)
            |> json(%{ok: false, error: "thread_not_found"})

          {:ok, %Thread{} = thr} ->
            idempotency_key = "forum.thread.unlock:#{tenant}:#{thr.id}"

            subject = %{type: "forum.thread", id: to_string(thr.id)}
            actor = %{type: "user", id: to_string(user.id)}

            request_id = request_id_from_logger_or_assigns(conn)

            payload = %{
              "thread_id" => to_string(thr.id),
              "subject" => %{"type" => "forum.thread", "id" => to_string(thr.id)}
            }

            metadata =
              %{
                "request_id" => request_id,
                "actor_role" => (role && to_string(role)) || nil,
                "source" => "web"
              }
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            with {:ok, %Directive{} = directive, directive_marker} <-
                   get_or_create_directive(
                     tenant,
                     %{
                       name: "forum.thread.unlock",
                       idempotency_key: idempotency_key,
                       requested_by_user_id: user.id,
                       payload: payload,
                       metadata: metadata
                     },
                     idempotency_key
                   ),
                 :ok <-
                   emit_directive_requested_signal(
                     tenant,
                     directive,
                     actor,
                     subject,
                     %{
                       "thread_id" => to_string(thr.id),
                       "directive_created" => directive_marker == :created
                     }
                   ),
                 {:ok, enqueued?} <- enqueue_directive_runner_job(directive, tenant) do
              json(conn, %{
                ok: true,
                tenant: tenant,
                directive_id: directive.id,
                directive_status: directive.status,
                directive_created: directive_marker == :created,
                enqueued: enqueued?,
                thread_id: thr.id
              })
            else
              {:error, err} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{ok: false, error: normalize_error(err)})

              {:discard, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{ok: false, error: reason})
            end

          {:error, err} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{ok: false, error: normalize_error(err)})
        end
    end
  end

  def hide_post(conn, %{"id" => post_id} = _params) do
    moderate_post(conn, post_id, %{
      directive_name: "forum.post.hide",
      idempotency_prefix: "forum.post.hide",
      subject_signal_name: "forum.post.hide.requested"
    })
  end

  def unhide_post(conn, %{"id" => post_id} = _params) do
    moderate_post(conn, post_id, %{
      directive_name: "forum.post.unhide",
      idempotency_prefix: "forum.post.unhide",
      subject_signal_name: "forum.post.unhide.requested"
    })
  end

  def delete_post(conn, %{"id" => post_id} = _params) do
    moderate_post(conn, post_id, %{
      directive_name: "forum.post.delete",
      idempotency_prefix: "forum.post.delete",
      subject_signal_name: "forum.post.delete.requested"
    })
  end

  defp moderate_post(conn, post_id, opts) when is_map(opts) do
    tenant = conn.assigns[:ash_tenant]
    user = conn.assigns[:current_user]
    role = conn.assigns[:current_role]

    cond do
      is_nil(user) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "authentication required"})

      not is_binary(tenant) or String.trim(tenant) == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "tenant context is missing"})

      role not in [:owner, :admin] ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "insufficient permissions"})

      not Code.ensure_loaded?(Directive) or not Code.ensure_loaded?(DirectiveRunner) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "directives are not implemented yet"})

      not Code.ensure_loaded?(Post) ->
        conn
        |> put_status(:not_implemented)
        |> json(%{ok: false, error: "forums posts are not implemented yet"})

      true ->
        case get_post_by_id(tenant, post_id) do
          {:ok, nil} ->
            conn
            |> put_status(:not_found)
            |> json(%{ok: false, error: "post_not_found"})

          {:ok, %Post{} = post} ->
            idempotency_key =
              "#{Map.fetch!(opts, :idempotency_prefix)}:#{tenant}:#{to_string(post.id)}"

            subject = %{type: "forum.post", id: to_string(post.id)}
            actor = %{type: "user", id: to_string(user.id)}
            request_id = request_id_from_logger_or_assigns(conn)

            payload = %{
              "post_id" => to_string(post.id),
              "thread_id" => to_string(post.thread_id),
              "subject" => %{"type" => "forum.post", "id" => to_string(post.id)}
            }

            metadata =
              %{
                "request_id" => request_id,
                "actor_role" => (role && to_string(role)) || nil,
                "source" => "web"
              }
              |> Map.reject(fn {_k, v} -> is_nil(v) end)

            with {:ok, %Directive{} = directive, directive_marker} <-
                   get_or_create_directive(
                     tenant,
                     %{
                       name: Map.fetch!(opts, :directive_name),
                       idempotency_key: idempotency_key,
                       requested_by_user_id: user.id,
                       payload: payload,
                       metadata: metadata
                     },
                     idempotency_key
                   ),
                 :ok <-
                   emit_directive_requested_signal(
                     tenant,
                     directive,
                     actor,
                     subject,
                     %{
                       "post_id" => to_string(post.id),
                       "thread_id" => to_string(post.thread_id),
                       "directive_created" => directive_marker == :created
                     }
                   ),
                 {:ok, enqueued?} <- enqueue_directive_runner_job(directive, tenant) do
              json(conn, %{
                ok: true,
                tenant: tenant,
                directive_id: directive.id,
                directive_status: directive.status,
                directive_created: directive_marker == :created,
                enqueued: enqueued?,
                post_id: post.id,
                thread_id: post.thread_id
              })
            else
              {:error, err} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{ok: false, error: normalize_error(err)})

              {:discard, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{ok: false, error: reason})
            end

          {:error, err} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{ok: false, error: normalize_error(err)})
        end
    end
  end

  defp get_post_by_id(tenant, post_id) when is_binary(tenant) and is_binary(post_id) do
    query =
      Post
      |> Ash.Query.for_read(:by_id, %{id: post_id})

    Ash.read_one(query, tenant: tenant)
  end

  defp get_post_by_id(_tenant, _post_id), do: {:ok, nil}

  defp get_or_create_directive(tenant, attrs, idempotency_key)
       when is_binary(tenant) and is_map(attrs) and is_binary(idempotency_key) do
    cond do
      not Code.ensure_loaded?(Directive) ->
        {:discard, "directives are not implemented yet"}

      true ->
        query =
          Directive
          |> Ash.Query.for_read(:by_idempotency_key, %{idempotency_key: idempotency_key})

        case Ash.read_one(query, tenant: tenant) do
          {:ok, %Directive{} = existing} ->
            {:ok, existing, :existing}

          {:ok, nil} ->
            changeset =
              Directive
              |> Ash.Changeset.for_create(:request, attrs)
              |> Ash.Changeset.set_tenant(tenant)

            case Ash.create(changeset) do
              {:ok, %Directive{} = created} -> {:ok, created, :created}
              {:error, err} -> {:error, err}
            end

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp get_or_create_directive(_tenant, _attrs, _idempotency_key),
    do: {:error, "invalid directive request"}

  defp enqueue_directive_runner_job(%Directive{} = directive, tenant) when is_binary(tenant) do
    cond do
      not Code.ensure_loaded?(Oban) ->
        {:ok, false}

      not Code.ensure_loaded?(DirectiveRunner) ->
        {:ok, false}

      not function_exported?(DirectiveRunner, :new, 1) ->
        {:ok, false}

      true ->
        job =
          DirectiveRunner.new(%{
            "directive_id" => directive.id,
            "tenant" => tenant
          })

        case Oban.insert(job) do
          {:ok, _job} -> {:ok, true}
          {:error, err} -> {:error, err}
        end
    end
  end

  defp enqueue_directive_runner_job(_directive, _tenant), do: {:ok, false}

  defp emit_directive_requested_signal(
         tenant,
         %Directive{} = directive,
         actor,
         subject,
         extra_payload
       )
       when is_binary(tenant) and is_map(extra_payload) do
    request_payload =
      %{
        "directive_id" => to_string(directive.id),
        "directive_name" => to_string(directive.name),
        "directive_status" => to_string(directive.status)
      }
      |> Map.merge(extra_payload)

    request_id = Map.get(directive.metadata || %{}, "request_id")

    metadata =
      %{
        request_id: request_id
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    dedupe_key = "directive.requested:#{tenant}:#{to_string(directive.id)}"

    _ =
      SignalBus.emit(
        tenant,
        "directive.requested",
        request_payload,
        metadata,
        dedupe_key: dedupe_key,
        actor: actor,
        subject: subject,
        source: "web"
      )

    :ok
  end

  defp emit_directive_requested_signal(_tenant, _directive, _actor, _subject, _extra_payload),
    do: :ok

  defp normalize_error(%{__exception__: true} = err), do: Exception.message(err)
  defp normalize_error(err) when is_binary(err), do: err
  defp normalize_error(err), do: inspect(err)

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
      inserted_at:
        case Map.get(category, :inserted_at) do
          %DateTime{} = dt ->
            DateTime.to_iso8601(dt)

          %NaiveDateTime{} = ndt ->
            ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

          _ ->
            nil
        end,
      updated_at:
        case Map.get(category, :updated_at) do
          %DateTime{} = dt ->
            DateTime.to_iso8601(dt)

          %NaiveDateTime{} = ndt ->
            ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

          _ ->
            nil
        end
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
        last_activity_at: iso_datetime(Map.get(stats, :last_activity_at))
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
      created_at: iso_datetime(Map.get(thread, :inserted_at)),
      updated_at: iso_datetime(Map.get(thread, :updated_at)),
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
      created_at: iso_datetime(Map.get(post, :inserted_at)),
      body: post.content,
      reactions: %{}
    }
  end

  defp load_thread_audit_signals(tenant, thread_id, limit \\ 200)

  defp load_thread_audit_signals(tenant, thread_id, limit)
       when is_binary(tenant) and is_binary(thread_id) and is_integer(limit) do
    cond do
      not Code.ensure_loaded?(Signal) ->
        []

      true ->
        # Best-effort: load recent tenant signals then filter in-memory.
        # This avoids brittle JSON-path filtering across Ash/Postgres versions.
        query =
          Signal
          |> Ash.Query.for_read(:recent, %{limit: min(max(limit, 1), 500)})

        case Ash.read(query, tenant: tenant) do
          {:ok, signals} when is_list(signals) ->
            signals
            |> Enum.filter(&signal_matches_thread?(&1, thread_id))
            |> Enum.map(&serialize_signal/1)

          _ ->
            []
        end
    end
  end

  defp load_thread_audit_signals(_tenant, _thread_id, _limit), do: []

  defp load_thread_audit_directives(tenant, thread_id, limit \\ 200)

  defp load_thread_audit_directives(tenant, thread_id, limit)
       when is_binary(tenant) and is_binary(thread_id) and is_integer(limit) do
    cond do
      not Code.ensure_loaded?(Directive) ->
        []

      true ->
        query =
          Directive
          |> Ash.Query.for_read(:recent, %{limit: min(max(limit, 1), 500)})

        case Ash.read(query, tenant: tenant) do
          {:ok, directives} when is_list(directives) ->
            directives
            |> Enum.filter(&directive_matches_thread?(&1, thread_id))
            |> Enum.map(&serialize_directive/1)

          _ ->
            []
        end
    end
  end

  defp load_thread_audit_directives(_tenant, _thread_id, _limit), do: []

  defp directive_matches_thread?(directive, thread_id)
       when is_map(directive) and is_binary(thread_id) do
    thread_id = String.trim(thread_id)

    cond do
      thread_id == "" ->
        false

      true ->
        payload = Map.get(directive, :payload) || %{}

        # Subject reference (preferred when present)
        subject = Map.get(payload, "subject") || Map.get(payload, :subject) || %{}
        subject_type = Map.get(subject, "type") || Map.get(subject, :type)
        subject_id = Map.get(subject, "id") || Map.get(subject, :id)

        payload_thread_id =
          Map.get(payload, "thread_id") ||
            Map.get(payload, :thread_id) ||
            Map.get(payload, "threadId") ||
            Map.get(payload, :threadId)

        (to_string(subject_type || "") == "forum.thread" and
           to_string(subject_id || "") == thread_id) or
          to_string(payload_thread_id || "") == thread_id
    end
  end

  defp directive_matches_thread?(_directive, _thread_id), do: false

  defp serialize_directive(directive) when is_map(directive) do
    payload = Map.get(directive, :payload) || Map.get(directive, "payload") || %{}
    metadata = Map.get(directive, :metadata) || Map.get(directive, "metadata") || %{}

    occurred_at =
      iso_datetime(
        Map.get(directive, :inserted_at) ||
          Map.get(directive, "inserted_at") ||
          Map.get(directive, :scheduled_at) ||
          Map.get(directive, "scheduled_at")
      )

    %{
      id: Map.get(directive, :id) || Map.get(directive, "id"),
      name: Map.get(directive, :name) || Map.get(directive, "name"),
      status: Map.get(directive, :status) || Map.get(directive, "status"),
      occurred_at: occurred_at,
      actor: %{
        type: "user",
        id:
          (Map.get(directive, :requested_by_user_id) || Map.get(directive, "requested_by_user_id"))
          |> case do
            nil -> nil
            v -> to_string(v)
          end
      },
      subject:
        case Map.get(payload, "subject") || Map.get(payload, :subject) do
          %{"type" => t, "id" => i} -> %{type: t, id: i}
          %{type: t, id: i} when not is_nil(t) and not is_nil(i) -> %{type: t, id: to_string(i)}
          _ -> %{type: nil, id: nil}
        end,
      payload: payload,
      metadata: metadata
    }
  end

  defp serialize_directive(_), do: %{}

  defp signal_matches_thread?(signal, thread_id) when is_map(signal) and is_binary(thread_id) do
    thread_id = String.trim(thread_id)

    cond do
      thread_id == "" ->
        false

      # Direct subject reference (preferred for thread-level signals)
      to_string(Map.get(signal, :subject_type) || "") == "forum.thread" and
          to_string(Map.get(signal, :subject_id) || "") == thread_id ->
        true

      # Payload reference (useful for post.created signals where subject is the post)
      true ->
        payload = Map.get(signal, :payload) || %{}

        payload_thread_id =
          Map.get(payload, "thread_id") ||
            Map.get(payload, :thread_id) ||
            Map.get(payload, "threadId") ||
            Map.get(payload, :threadId)

        to_string(payload_thread_id || "") == thread_id
    end
  end

  defp signal_matches_thread?(_signal, _thread_id), do: false

  defp serialize_signal(signal) when is_map(signal) do
    %{
      id: Map.get(signal, :id) || Map.get(signal, "id"),
      name: Map.get(signal, :name) || Map.get(signal, "name"),
      dedupe_key: Map.get(signal, :dedupe_key) || Map.get(signal, "dedupe_key"),
      source: Map.get(signal, :source) || Map.get(signal, "source"),
      occurred_at: iso_datetime(Map.get(signal, :occurred_at) || Map.get(signal, "occurred_at")),
      inserted_at: iso_datetime(Map.get(signal, :inserted_at) || Map.get(signal, "inserted_at")),
      actor: %{
        type: Map.get(signal, :actor_type) || Map.get(signal, "actor_type"),
        id: Map.get(signal, :actor_id) || Map.get(signal, "actor_id")
      },
      subject: %{
        type: Map.get(signal, :subject_type) || Map.get(signal, "subject_type"),
        id: Map.get(signal, :subject_id) || Map.get(signal, "subject_id")
      },
      payload: Map.get(signal, :payload) || Map.get(signal, "payload") || %{},
      metadata: Map.get(signal, :metadata) || Map.get(signal, "metadata") || %{}
    }
  end

  defp serialize_signal(_), do: %{}

  defp iso_datetime(nil), do: nil
  defp iso_datetime(v) when is_binary(v), do: String.trim(v)

  defp iso_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp iso_datetime(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp iso_datetime(v), do: v |> to_string() |> String.trim()

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = dt), do: dt

  defp to_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_datetime(v) when is_binary(v) do
    case DateTime.from_iso8601(String.trim(v)) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp to_datetime(_), do: nil

  defp max_datetime(a, b) do
    a = to_datetime(a)
    b = to_datetime(b)

    cond do
      is_nil(a) -> b
      is_nil(b) -> a
      DateTime.compare(b, a) == :gt -> b
      true -> a
    end
  end

  defp uuid_string?(id) when is_binary(id) do
    Regex.match?(
      ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/,
      id
    )
  end

  defp uuid_string?(_), do: false

  defp category_exists?(tenant, category_id)
       when is_binary(tenant) and is_binary(category_id) do
    id = String.trim(category_id)

    cond do
      id == "" ->
        false

      not uuid_string?(id) ->
        false

      true ->
        case get_category_by_id(tenant, id) do
          {:ok, %Category{} = category} -> category.status == :active
          _ -> false
        end
    end
  end

  defp category_exists?(_tenant, _category_id), do: false

  defp get_category_by_id(tenant, id) when is_binary(tenant) do
    query =
      Category
      |> Ash.Query.for_read(:by_id, %{id: id})

    Ash.read_one(query, tenant: tenant)
  end

  defp get_thread_by_id(tenant, id) when is_binary(tenant) do
    query =
      Thread
      |> Ash.Query.for_read(:by_id, %{id: id})

    Ash.read_one(query, tenant: tenant)
  end
end
