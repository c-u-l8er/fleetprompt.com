defmodule FleetPrompt.Directives.DirectiveRunnerTest do
  use FleetPrompt.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias FleetPrompt.Accounts.{Organization, User}
  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Directives.Directive
  alias FleetPrompt.Jobs.DirectiveRunner
  alias FleetPrompt.Packages.{Installation, Package}

  setup do
    uniq = System.unique_integer([:positive])

    {:ok, org} =
      Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Directive Runner Test Org #{uniq}",
        slug: "directive_runner_test_#{uniq}",
        tier: :pro
      })
      |> Ash.create()

    {:ok, user} =
      User
      |> Ash.Changeset.for_create(:create, %{
        email: "directive-runner-#{uniq}@example.com",
        name: "Directive Runner User #{uniq}",
        password: "password123",
        organization_id: org.id,
        role: :admin
      })
      |> Ash.create()

    tenant = "org_#{org.slug}"

    %{org: org, user: user, tenant: tenant}
  end

  defp create_package!(overrides \\ %{}) do
    uniq = System.unique_integer([:positive])

    base = %{
      name: "Directive Runner Package #{uniq}",
      slug: "directive-runner-package-#{uniq}",
      version: "1.0.0",
      description: "Package fixture for DirectiveRunner tests",
      category: :operations,
      pricing_model: :free,
      min_fleet_prompt_tier: :free,
      includes: %{
        "agents" => [
          %{
            "name" => "Dispatcher",
            "description" => "Intelligent scheduling",
            "system_prompt" => "You are a dispatcher agent. Optimize schedules and assignments."
          }
        ],
        "workflows" => [],
        "skills" => [],
        "tools" => []
      },
      install_count: 0,
      is_published: true
    }

    params = Map.merge(base, overrides)

    case Package |> Ash.Changeset.for_create(:create, params) |> Ash.create() do
      {:ok, pkg} -> pkg
      {:error, err} -> raise "Failed to create package fixture: #{Exception.message(err)}"
    end
  end

  defp create_installation!(org_or_tenant, user, pkg, overrides) do
    uniq = System.unique_integer([:positive])

    base = %{
      package_slug: pkg.slug,
      package_version: pkg.version,
      package_name: pkg.name,
      installed_by_user_id: user.id,
      config: %{},
      idempotency_key: "test-install-idem-#{uniq}"
    }

    params = Map.merge(base, overrides)

    changeset =
      Installation
      |> Ash.Changeset.for_create(:request_install, params)
      |> Ash.Changeset.set_tenant(org_or_tenant)

    case Ash.create(changeset) do
      {:ok, installation} -> installation
      {:error, err} -> raise "Failed to create installation fixture: #{Exception.message(err)}"
    end
  end

  defp mark_installation_installed!(%Installation{} = installation, tenant) do
    installation
    |> Ash.Changeset.for_update(:mark_installed, %{})
    |> Ash.Changeset.set_tenant(tenant)
    |> Ash.update!()
  end

  defp create_directive!(tenant, user, name, idempotency_key, payload) do
    changeset =
      Directive
      |> Ash.Changeset.for_create(:request, %{
        name: name,
        idempotency_key: idempotency_key,
        requested_by_user_id: user.id,
        payload: payload,
        metadata: %{"source" => "test"}
      })
      |> Ash.Changeset.set_tenant(tenant)

    case Ash.create(changeset) do
      {:ok, directive} -> directive
      {:error, err} -> raise "Failed to create directive fixture: #{Exception.message(err)}"
    end
  end

  defp reload_directive!(tenant, directive_id) do
    query =
      Directive
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^directive_id))

    case Ash.read_one(query, tenant: tenant) do
      {:ok, %Directive{} = directive} -> directive
      {:ok, nil} -> raise "Expected directive #{directive_id} to exist in tenant #{tenant}"
      {:error, err} -> raise "Failed to reload directive: #{Exception.message(err)}"
    end
  end

  defp load_installation_by_slug(tenant, slug) do
    query =
      Installation
      |> Ash.Query.for_read(:by_slug, %{package_slug: slug})

    Ash.read_one(query, tenant: tenant)
  end

  defp create_agent_matching_package!(tenant, pkg) do
    includes = Map.get(pkg, :includes) || %{}
    agents = Map.get(includes, "agents") || Map.get(includes, :agents) || []
    first = agents |> List.wrap() |> List.first() || %{}

    name = Map.get(first, "name") || Map.get(first, :name) || "Dispatcher"

    system_prompt =
      Map.get(first, "system_prompt") || Map.get(first, :system_prompt) || "You are helpful."

    changeset =
      Agent
      |> Ash.Changeset.for_create(:create, %{
        name: name,
        system_prompt: system_prompt,
        description: "Fixture agent created for uninstall test"
      })
      |> Ash.Changeset.set_tenant(tenant)

    Ash.create!(changeset)
    {String.trim(name), String.trim(system_prompt)}
  end

  defp count_agents_by_signature!(tenant, name, system_prompt) do
    query =
      Agent
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(name == ^name and system_prompt == ^system_prompt))

    case Ash.read(query, tenant: tenant) do
      {:ok, agents} -> length(agents)
      {:error, err} -> raise "Failed to read agents: #{Exception.message(err)}"
    end
  end

  test "DirectiveRunner executes package.install and marks directive succeeded (when install is already installed so no enqueue needed)",
       %{org: org, user: user, tenant: tenant} do
    pkg = create_package!()

    shared_install_key = "package.install:#{tenant}:#{pkg.slug}@#{pkg.version}"

    installation =
      create_installation!(org, user, pkg, %{
        idempotency_key: shared_install_key
      })
      |> mark_installation_installed!(tenant)

    directive =
      create_directive!(
        tenant,
        user,
        "package.install",
        shared_install_key,
        %{
          "slug" => pkg.slug,
          "version" => pkg.version,
          "installation_id" => installation.id,
          "config" => %{}
        }
      )

    job = %Oban.Job{
      id: 123,
      attempt: 1,
      max_attempts: 10,
      queue: "default",
      args: %{
        "directive_id" => directive.id,
        "tenant" => tenant
      }
    }

    assert :ok = DirectiveRunner.perform(job)

    directive = reload_directive!(tenant, directive.id)
    assert directive.status == :succeeded
    assert directive.started_at
    assert directive.completed_at
    assert is_map(directive.result)

    type = Map.get(directive.result, "type") || Map.get(directive.result, :type)
    assert type == "package.install"

    installation_id =
      Map.get(directive.result, "installation_id") || Map.get(directive.result, :installation_id)

    assert installation_id == installation.id

    # Installation remains installed
    {:ok, installation_after} = load_installation_by_slug(tenant, pkg.slug)
    assert installation_after.status == :installed
    assert installation_after.installed_at
  end

  test "DirectiveRunner executes package.uninstall, deletes installation, and purges matching agents when purge=true",
       %{org: org, user: user, tenant: tenant} do
    pkg = create_package!()

    installation =
      create_installation!(org, user, pkg, %{
        idempotency_key: "any-key-#{System.unique_integer([:positive])}"
      })

    {agent_name, agent_prompt} = create_agent_matching_package!(tenant, pkg)
    assert count_agents_by_signature!(tenant, agent_name, agent_prompt) == 1

    uninstall_key = "package.uninstall:#{tenant}:#{pkg.slug}"

    directive =
      create_directive!(
        tenant,
        user,
        "package.uninstall",
        uninstall_key,
        %{
          "slug" => pkg.slug,
          "purge" => true
        }
      )

    job = %Oban.Job{
      id: 456,
      attempt: 1,
      max_attempts: 10,
      queue: "default",
      args: %{
        "directive_id" => directive.id,
        "tenant" => tenant
      }
    }

    assert :ok = DirectiveRunner.perform(job)

    directive = reload_directive!(tenant, directive.id)
    assert directive.status == :succeeded
    assert directive.started_at
    assert directive.completed_at
    type = Map.get(directive.result, "type") || Map.get(directive.result, :type)
    assert type == "package.uninstall"

    installation_removed =
      Map.get(directive.result, "installation_removed") ||
        Map.get(directive.result, :installation_removed)

    assert installation_removed == true

    purged_agents =
      Map.get(directive.result, "purged_agents") || Map.get(directive.result, :purged_agents)

    assert is_integer(purged_agents)

    # Installation is removed
    assert {:ok, nil} = load_installation_by_slug(tenant, pkg.slug)

    # Agent is purged (best-effort: only deletes if it matches package signature)
    assert count_agents_by_signature!(tenant, agent_name, agent_prompt) == 0

    # Ensure we didn't accidentally depend on the installation existing after uninstall
    refute is_nil(installation.id)
  end

  test "DirectiveRunner executes forum.thread.lock and locks the thread",
       %{user: user, tenant: tenant} do
    uniq = System.unique_integer([:positive])

    {:ok, category} =
      FleetPrompt.Forums.Category
      |> Ash.Changeset.for_create(:create, %{
        slug: "general-#{uniq}",
        name: "General #{uniq}",
        status: :active
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()

    {:ok, thread} =
      FleetPrompt.Forums.Thread
      |> Ash.Changeset.for_create(:create, %{
        category_id: category.id,
        title: "Thread #{uniq}",
        status: :open,
        created_by_user_id: user.id
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()

    lock_key = "forum.thread.lock:#{tenant}:#{thread.id}"

    directive =
      create_directive!(
        tenant,
        user,
        "forum.thread.lock",
        lock_key,
        %{
          "thread_id" => to_string(thread.id),
          "subject" => %{"type" => "forum.thread", "id" => to_string(thread.id)}
        }
      )

    job = %Oban.Job{
      id: 9001,
      attempt: 1,
      max_attempts: 10,
      queue: "default",
      args: %{
        "directive_id" => directive.id,
        "tenant" => tenant
      }
    }

    assert :ok = DirectiveRunner.perform(job)

    directive = reload_directive!(tenant, directive.id)
    assert directive.status == :succeeded

    type = Map.get(directive.result, "type") || Map.get(directive.result, :type)
    assert type == "forum.thread.lock"

    {:ok, thread_after} =
      FleetPrompt.Forums.Thread
      |> Ash.Query.for_read(:by_id, %{id: thread.id})
      |> Ash.read_one(tenant: tenant)

    assert thread_after.status == :locked
  end

  test "DirectiveRunner executes forum.post.hide and hides the post",
       %{user: user, tenant: tenant} do
    uniq = System.unique_integer([:positive])

    {:ok, category} =
      FleetPrompt.Forums.Category
      |> Ash.Changeset.for_create(:create, %{
        slug: "general-hide-#{uniq}",
        name: "General Hide #{uniq}",
        status: :active
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()

    {:ok, thread} =
      FleetPrompt.Forums.Thread
      |> Ash.Changeset.for_create(:create, %{
        category_id: category.id,
        title: "Thread Hide #{uniq}",
        status: :open,
        created_by_user_id: user.id
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()

    {:ok, post} =
      FleetPrompt.Forums.Post
      |> Ash.Changeset.for_create(:create, %{
        thread_id: thread.id,
        content: "Hello from test #{uniq}",
        author_type: :human,
        author_id: to_string(user.id)
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()

    hide_key = "forum.post.hide:#{tenant}:#{post.id}"

    directive =
      create_directive!(
        tenant,
        user,
        "forum.post.hide",
        hide_key,
        %{
          "post_id" => to_string(post.id),
          "thread_id" => to_string(thread.id),
          "subject" => %{"type" => "forum.post", "id" => to_string(post.id)}
        }
      )

    job = %Oban.Job{
      id: 9002,
      attempt: 1,
      max_attempts: 10,
      queue: "default",
      args: %{
        "directive_id" => directive.id,
        "tenant" => tenant
      }
    }

    assert :ok = DirectiveRunner.perform(job)

    directive = reload_directive!(tenant, directive.id)
    assert directive.status == :succeeded

    type = Map.get(directive.result, "type") || Map.get(directive.result, :type)
    assert type == "forum.post.hide"

    {:ok, post_after} =
      FleetPrompt.Forums.Post
      |> Ash.Query.for_read(:by_id, %{id: post.id})
      |> Ash.read_one(tenant: tenant)

    assert post_after.status == :hidden
  end
end
