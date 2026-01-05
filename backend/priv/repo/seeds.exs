# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This seed script uses Ash resources so it exercises:
# - Organization creation (public schema, tenant schemas managed via AshPostgres manage_tenant)
# - User creation (public schema, belongs_to organization)
# - Skills catalog (public schema, global)
# - Agent creation (tenant schema via `Ash.Changeset.set_tenant/2`)
#
# NOTE: This script expects Postgres extensions uuid-ossp + citext to be installed,
# and Ash migrations for these resources to have been run.

alias FleetPrompt.Accounts.Organization
alias FleetPrompt.Accounts.User
alias FleetPrompt.Skills.Skill
alias FleetPrompt.Agents.Agent

import Ash.Expr
require Ash.Query

# Helper to print an Ash error nicely without crashing with opaque terms
format_error = fn
  %Ash.Error.Invalid{errors: errors} ->
    Enum.map_join(errors, "\n", fn e -> "  - " <> Exception.message(e) end)

  other ->
    Exception.message(other)
end

IO.puts("\n== FleetPrompt Seeds ==")

#
# 1) Create demo organization (tenant schema: org_demo)
#
org_params = %{
  name: "Demo Company",
  slug: "demo",
  tier: :pro
}

org =
  case Organization |> Ash.Changeset.for_create(:create, org_params) |> Ash.create() do
    {:ok, org} ->
      IO.puts("OK: Created organization: #{org.name} (tenant: org_#{org.slug})")
      org

    {:error, error} ->
      IO.puts(
        "INFO: Organization create failed (likely already exists). Trying to load by slug..."
      )

      case Organization
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(expr(slug == ^org_params.slug))
           |> Ash.read_one() do
        {:ok, org} when not is_nil(org) ->
          IO.puts("OK: Loaded existing organization: #{org.name} (tenant: org_#{org.slug})")
          org

        {:ok, nil} ->
          raise """
          Could not create or load demo organization.
          Create error:
          #{format_error.(error)}
          """

        {:error, read_error} ->
          raise """
          Could not create demo organization and failed to load existing.
          Create error:
          #{format_error.(error)}

          Read error:
          #{format_error.(read_error)}
          """
      end
  end

#
# 2) Create admin user
#
admin_params = %{
  email: "admin@demo.com",
  name: "Admin User",
  password: "password123",
  organization_id: org.id,
  role: :admin
}

_admin =
  case User |> Ash.Changeset.for_create(:create, admin_params) |> Ash.create() do
    {:ok, admin} ->
      IO.puts("OK: Created admin user: #{admin.email}")
      admin

    {:error, error} ->
      IO.puts(
        "INFO: Admin user create failed (likely already exists). Trying to load by email..."
      )

      case User
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(expr(email == ^admin_params.email))
           |> Ash.read_one() do
        {:ok, admin} when not is_nil(admin) ->
          IO.puts("OK: Loaded existing admin user: #{admin.email}")
          admin

        {:ok, nil} ->
          raise """
          Could not create or load admin user.
          Create error:
          #{format_error.(error)}
          """

        {:error, read_error} ->
          raise """
          Could not create admin user and failed to load existing.
          Create error:
          #{format_error.(error)}

          Read error:
          #{format_error.(read_error)}
          """
      end
  end

#
# 3) Create demo skills (global)
#
skills_data = [
  %{
    name: "Web Research",
    slug: "web-research",
    description: "Advanced web search and information gathering",
    category: :research,
    tier_required: :free,
    system_prompt_enhancement: """
    You have access to web search capabilities. When researching:
    1. Search for authoritative sources
    2. Cross-reference multiple sources
    3. Evaluate source credibility
    4. Cite all sources in your response
    """,
    tools: ["web_search", "web_fetch"],
    is_official: true
  },
  %{
    name: "Code Analysis",
    slug: "code-analysis",
    description: "Analyze and review code for best practices",
    category: :coding,
    tier_required: :pro,
    system_prompt_enhancement: """
    You are an expert code reviewer. When analyzing code:
    1. Check for security vulnerabilities
    2. Assess code quality and maintainability
    3. Suggest improvements and optimizations
    4. Follow language-specific best practices
    """,
    tools: ["ast_parse", "static_analysis"],
    is_official: true
  },
  %{
    name: "Customer Communication",
    slug: "customer-communication",
    description: "Professional customer service and support",
    category: :communication,
    tier_required: :free,
    system_prompt_enhancement: """
    You are a professional customer service representative.
    - Be empathetic and understanding
    - Provide clear, actionable solutions
    - Maintain a friendly, professional tone
    - Ask clarifying questions when needed
    """,
    tools: ["send_email", "send_sms"],
    is_official: true
  }
]

Enum.each(skills_data, fn skill_data ->
  case Skill |> Ash.Changeset.for_create(:create, skill_data) |> Ash.create() do
    {:ok, skill} ->
      IO.puts("OK: Created skill: #{skill.name}")

    {:error, error} ->
      IO.puts(
        "INFO: Skill #{skill_data.slug} create failed (likely exists). Trying to load by slug..."
      )

      case Skill
           |> Ash.Query.for_read(:read)
           |> Ash.Query.filter(expr(slug == ^skill_data.slug))
           |> Ash.read_one() do
        {:ok, skill} when not is_nil(skill) ->
          IO.puts("OK: Loaded existing skill: #{skill.name}")

        {:ok, nil} ->
          IO.puts("""
          WARN: Could not create or load skill #{skill_data.slug}.
          Error:
          #{format_error.(error)}
          """)

        {:error, read_error} ->
          IO.puts("""
          WARN: Could not create skill #{skill_data.slug} and failed to load existing.
          Create error:
          #{format_error.(error)}

          Read error:
          #{format_error.(read_error)}
          """)
      end
  end
end)

#
# 4) Create demo agent in org tenant context
#
agent_params = %{
  name: "Research Assistant",
  description: "AI research assistant with web search capabilities",
  system_prompt: """
  You are a research assistant. Your job is to:
  1. Understand the user's research question
  2. Search for relevant information
  3. Synthesize findings into clear summaries
  4. Cite all sources

  Be thorough, accurate, and objective.
  """,
  config: %{
    "model" => "claude-sonnet-4",
    "max_tokens" => 4096,
    "temperature" => 0.7
  }
}

_agent =
  case Agent
       |> Ash.Changeset.for_create(:create, agent_params)
       |> Ash.Changeset.set_tenant(org)
       |> Ash.create() do
    {:ok, agent} ->
      IO.puts(
        "OK: Created demo agent in tenant org_#{org.slug}: #{agent.name} (state: #{agent.state})"
      )

      agent

    {:error, error} ->
      IO.puts("""
      WARN: Could not create demo agent (it may already exist, or migrations/tenant setup are incomplete).
      Error:
      #{format_error.(error)}
      """)
  end

IO.puts("\nOK: Seed data finished.")
IO.puts("\nLogin credentials:")
IO.puts("  Email: admin@demo.com")
IO.puts("  Password: password123")
IO.puts("\nAdmin panel:")
IO.puts("  http://localhost:4000/admin")
