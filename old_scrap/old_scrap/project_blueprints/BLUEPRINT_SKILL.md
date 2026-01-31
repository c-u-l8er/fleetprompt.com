# Blueprint: Skill (composable capability)

This blueprint describes how to design Skills in FleetPrompt.

Current implementation anchor (Phase 1):
- [`FleetPrompt.Skills.Skill`](backend/lib/fleet_prompt/skills/skill.ex:1)

## 1) What a Skill is (FleetPrompt stance)

A Skill is a reusable capability that:
- augments prompts (system_prompt_enhancement)
- declares tool requirements
- can be packaged and reused across agents/workflows

In Phase 1, Skills are **global** records (public schema). Over time, FleetPrompt may support:
- tenant-specific skills
- package-installed skills

## 2) Current data model

Key fields in [`FleetPrompt.Skills.Skill`](backend/lib/fleet_prompt/skills/skill.ex:14):
- `slug` (unique)
- `category`
- `tier_required`
- `system_prompt_enhancement`
- `tools` (list of tool names)
- `is_official`

## 3) Skill contract (recommended)

A skill should declare:

1. Prompt enhancement
- a short, composable snippet
- no secrets
- no tenant-specific data baked into the global skill record

2. Tool requirements
- a list of tool names required to fulfill the skill
- these tools must exist in [`FleetPrompt.AI.Tools.definitions/0`](backend/lib/fleet_prompt/ai/tools.ex:10)

3. Guardrails
- what the skill must not do
- whether the skill is allowed to request directives (future)

## 4) Skill spec template

```json
{
  "skill": {
    "name": "Forum Duplicate Detection",
    "slug": "forum-duplicate-detection",
    "category": "operations",
    "tier_required": "free",
    "system_prompt_enhancement": "When a new thread is created, search for related threads and suggest links...",
    "tools": ["forum_threads_search"],
    "guardrails": {
      "side_effects": "none",
      "notes": "Do not create posts directly; propose a directive instead."
    }
  }
}
```

## 5) Composition rules

- Skills should be small and reusable.
- Prefer composing multiple skills rather than writing one giant system prompt.

## 6) Checklist for adding a new skill

- [ ] Unique `slug`.
- [ ] Prompt enhancement is safe and general.
- [ ] Tool list is explicit.
- [ ] No secrets in the skill body.
- [ ] Any side effects are routed to directives (do not embed them in the prompt).
