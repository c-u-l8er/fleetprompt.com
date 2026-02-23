
defmodule FleetPrompt.AI.Tools do
  @moduledoc """
  Defines tools available to the LLM and handles their execution.
  """

  require Ash.Query
  alias FleetPrompt.Forums.{Category, Thread, Post}

  def definitions do
    [
      %{
        type: "function",
        function: %{
          name: "create_forum_category",
          description: "Create a new forum category.",
          parameters: %{
            type: "object",
            properties: %{
              slug: %{type: "string", description: "URL-friendly slug (e.g. 'announcements')"},
              name: %{type: "string", description: "Display name (e.g. 'Announcements')"},
              description: %{type: "string", description: "Optional description"}
            },
            required: ["slug", "name"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_forum_thread",
          description: "Create a new discussion thread in a category.",
          parameters: %{
            type: "object",
            properties: %{
              category_id: %{type: "string", description: "UUID of the category"},
              title: %{type: "string", description: "Title of the thread"},
              created_by_user_id: %{
                type: "string",
                description: "UUID of the author (server will default to the current user if omitted)"
              }
            },
            required: ["category_id", "title"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_forum_post",
          description: "Reply to a thread.",
          parameters: %{
            type: "object",
            properties: %{
              thread_id: %{type: "string", description: "UUID of the thread"},
              content: %{type: "string", description: "Content of the post"},
              author_id: %{type: "string", description: "UUID of the author (server will default to the current user if omitted)"}
            },
            required: ["thread_id", "content"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "list_forum_categories",
          description: "List all forum categories.",
          parameters: %{
            type: "object",
            properties: %{},
            required: []
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "list_forum_threads",
          description: "List threads in a category.",
          parameters: %{
            type: "object",
            properties: %{
              category_id: %{type: "string", description: "UUID of the category"}
            },
            required: ["category_id"]
          }
        }
      }
    ]
  end

  @doc """
  Execute a tool by name.

  Backwards compatible 3-arity form.
  """
  def execute(name, args, tenant), do: execute(name, args, tenant, %{})

  @doc """
  Execute a tool by name with additional context.

  Context currently supports:
  - `:actor_user_id` (string UUID)
  """
  def execute("create_forum_category", args, tenant, _ctx) do
    Category
    |> Ash.Changeset.for_create(:create, args)
    |> Ash.create(tenant: tenant)
    |> case do
      {:ok, category} -> {:ok, "Created category: #{category.name} (ID: #{category.id})"}
      {:error, error} -> {:error, "Failed to create category: #{inspect(error)}"}
    end
  end

  def execute("create_forum_thread", args, tenant, ctx) do
    args = maybe_put_actor(args, "created_by_user_id", ctx)

    Thread
    |> Ash.Changeset.for_create(:create, args)
    |> Ash.create(tenant: tenant)
    |> case do
      {:ok, thread} -> {:ok, "Created thread: #{thread.title} (ID: #{thread.id})"}
      {:error, error} -> {:error, "Failed to create thread: #{inspect(error)}"}
    end
  end

  def execute("create_forum_post", args, tenant, ctx) do
    args =
      args
      |> maybe_put_actor("author_id", ctx)
      |> Map.put_new("author_type", "human")

    Post
    |> Ash.Changeset.for_create(:create, args)
    |> Ash.create(tenant: tenant)
    |> case do
      {:ok, post} -> {:ok, "Created post (ID: #{post.id})"}
      {:error, error} -> {:error, "Failed to create post: #{inspect(error)}"}
    end
  end

  def execute("list_forum_categories", _args, tenant, _ctx) do
    Category
    |> Ash.read(tenant: tenant)
    |> case do
      {:ok, categories} ->
        list = Enum.map(categories, fn c -> "- #{c.name} (ID: #{c.id}, Slug: #{c.slug})" end)
        {:ok, Enum.join(list, "\n")}

      {:error, error} ->
        {:error, "Failed to list categories: #{inspect(error)}"}
    end
  end

  def execute("list_forum_threads", %{"category_id" => category_id}, tenant, _ctx) do
    Thread
    |> Ash.Query.for_read(:by_category, %{category_id: category_id})
    |> Ash.read(tenant: tenant)
    |> case do
      {:ok, threads} ->
        list = Enum.map(threads, fn t -> "- #{t.title} (ID: #{t.id})" end)
        {:ok, Enum.join(list, "\n")}

      {:error, error} ->
        {:error, "Failed to list threads: #{inspect(error)}"}
    end
  end

  def execute(name, _args, _tenant, _ctx), do: {:error, "Unknown tool: #{name}"}

  defp maybe_put_actor(args, key, %{actor_user_id: actor_user_id}) when is_binary(actor_user_id) do
    case Map.get(args, key) do
      v when is_binary(v) and v != "" -> args
      _ -> Map.put(args, key, actor_user_id)
    end
  end

  defp maybe_put_actor(args, _key, _ctx), do: args
end
