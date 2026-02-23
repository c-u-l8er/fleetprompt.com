defmodule FleetPrompt.Agents.AgentTest do
  use FleetPrompt.DataCase, async: false

  alias FleetPrompt.Accounts.Organization
  alias FleetPrompt.Agents.Agent

  setup do
    uniq = System.unique_integer([:positive])

    {:ok, org} =
      Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Org #{uniq}",
        slug: "test_org_#{uniq}",
        tier: :pro
      })
      |> Ash.create()

    %{org: org}
  end

  test "creates agent in tenant context", %{org: org} do
    {:ok, agent} =
      Agent
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Agent",
        description: "A test agent",
        system_prompt: "You are helpful."
      })
      |> Ash.Changeset.set_tenant(org)
      |> Ash.create()

    assert agent.name == "Test Agent"
    assert agent.state == :draft
  end

  test "agent state transition: deploy", %{org: org} do
    {:ok, agent} =
      Agent
      |> Ash.Changeset.for_create(:create, %{
        name: "Deployable Agent",
        system_prompt: "You are helpful."
      })
      |> Ash.Changeset.set_tenant(org)
      |> Ash.create()

    {:ok, agent} =
      agent
      |> Ash.Changeset.for_update(:deploy)
      |> Ash.Changeset.set_tenant(org)
      |> Ash.update()

    assert agent.state == :deploying
  end
end
