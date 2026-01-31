defmodule FleetPrompt.Packages.PackageInstallerTest do
  use FleetPrompt.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias FleetPrompt.Accounts.{Organization, User}
  alias FleetPrompt.Agents.Agent
  alias FleetPrompt.Jobs.PackageInstaller
  alias FleetPrompt.Packages.{Installation, Package}

  setup do
    uniq = System.unique_integer([:positive])

    {:ok, org} =
      Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Pkg Install Test Org #{uniq}",
        slug: "pkg_install_test_#{uniq}",
        tier: :pro
      })
      |> Ash.create()

    {:ok, user} =
      User
      |> Ash.Changeset.for_create(:create, %{
        email: "pkg-install-#{uniq}@example.com",
        name: "Pkg Install User #{uniq}",
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
      name: "Test Package #{uniq}",
      slug: "test-package-#{uniq}",
      version: "1.0.0",
      description: "Test package for installer worker",
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

  defp create_installation!(org, user, pkg, overrides \\ %{}) do
    uniq = System.unique_integer([:positive])

    base = %{
      package_slug: pkg.slug,
      package_version: pkg.version,
      package_name: pkg.name,
      installed_by_user_id: user.id,
      config: %{},
      idempotency_key: "test-idem-#{uniq}"
    }

    params = Map.merge(base, overrides)

    case Installation
         |> Ash.Changeset.for_create(:request_install, params)
         |> Ash.Changeset.set_tenant(org)
         |> Ash.create() do
      {:ok, installation} -> installation
      {:error, err} -> raise "Failed to create installation fixture: #{Exception.message(err)}"
    end
  end

  defp reload_installation!(installation_id, tenant) do
    query =
      Installation
      |> Ash.Query.for_read(:read)
      |> Ash.Query.filter(expr(id == ^installation_id))

    case Ash.read_one(query, tenant: tenant) do
      {:ok, %Installation{} = installation} -> installation
      {:ok, nil} -> raise "Expected installation #{installation_id} to exist in tenant #{tenant}"
      {:error, err} -> raise "Failed to reload installation: #{Exception.message(err)}"
    end
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

  test "installs package agents into tenant and marks installation installed", %{
    org: org,
    user: user,
    tenant: tenant
  } do
    pkg = create_package!()

    installation = create_installation!(org, user, pkg)

    job = %Oban.Job{
      args: %{
        "installation_id" => installation.id,
        "tenant" => tenant
      }
    }

    assert :ok = PackageInstaller.perform(job)

    installation = reload_installation!(installation.id, tenant)
    assert installation.status == :installed
    assert installation.enabled == true
    assert installation.installed_at
    assert is_nil(installation.last_error)

    dispatcher_prompt = "You are a dispatcher agent. Optimize schedules and assignments."
    assert count_agents_by_signature!(tenant, "Dispatcher", dispatcher_prompt) == 1

    # Best-effort: package stats were bumped in the public schema
    reloaded_pkg =
      Package
      |> Ash.Query.for_read(:by_slug, %{slug: pkg.slug})
      |> Ash.read_one!()

    assert reloaded_pkg.install_count >= 1
  end

  test "is retry-safe: running the installer twice does not create duplicate agents", %{
    org: org,
    user: user,
    tenant: tenant
  } do
    pkg = create_package!()

    installation = create_installation!(org, user, pkg)

    job = %Oban.Job{
      args: %{
        "installation_id" => installation.id,
        "tenant" => tenant
      }
    }

    assert :ok = PackageInstaller.perform(job)
    assert :ok = PackageInstaller.perform(job)

    dispatcher_prompt = "You are a dispatcher agent. Optimize schedules and assignments."
    assert count_agents_by_signature!(tenant, "Dispatcher", dispatcher_prompt) == 1

    installation = reload_installation!(installation.id, tenant)
    assert installation.status == :installed
  end

  test "marks installation failed when requested version does not match registry", %{
    org: org,
    user: user,
    tenant: tenant
  } do
    pkg = create_package!(%{version: "1.0.0"})

    installation =
      create_installation!(org, user, pkg, %{
        package_version: "9.9.9"
      })

    job = %Oban.Job{
      args: %{
        "installation_id" => installation.id,
        "tenant" => tenant
      }
    }

    assert {:error, msg} = PackageInstaller.perform(job)
    assert is_binary(msg)

    installation = reload_installation!(installation.id, tenant)
    assert installation.status == :failed
    assert installation.last_error
    assert installation.last_error_at
  end

  test "marks installation failed when package is missing from registry", %{
    org: org,
    user: user,
    tenant: tenant
  } do
    # Create an installation that points at a non-existent package slug/version.
    installation =
      create_installation!(org, user, create_package!(), %{
        package_slug: "nonexistent-package-slug",
        package_version: "1.2.3"
      })

    job = %Oban.Job{
      args: %{
        "installation_id" => installation.id,
        "tenant" => tenant
      }
    }

    assert {:error, msg} = PackageInstaller.perform(job)
    assert is_binary(msg)

    installation = reload_installation!(installation.id, tenant)
    assert installation.status == :failed
    assert installation.last_error
    assert installation.last_error_at
  end
end
