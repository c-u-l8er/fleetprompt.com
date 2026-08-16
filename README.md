# FleetPrompt

Registry for agents — publish one, install one, and check what it claims before
you run it. Elixir/OTP with a Phoenix API and an MCP server. Part of the
[ComputeDriven](https://computedriven.com) world.

**Written 2026-08-16.** This repository had no README before that date. Every
figure below was measured that day with the command beside it.

---

## Status, honestly

| | |
|---|---|
| Version | `0.1.0` (`mix.exs`, app `:fleet_prompt`) |
| Tests | **112 passing, 0 failures, 2 excluded** — `mix test` |
| Marketing page | **live** — `https://fleetprompt.com` answers 200 |
| Application | **live on Fly** as app `fleetprompt` — `https://app.fleetprompt.com` answers 200, and `POST /mcp` returns 200 |
| Evidence rung | `live_deployed` |

**The test count is 112, not 121.** `COMPUTEDRIVEN_POSITIONING_PLAN.md` says 121;
the suite says 112 with 2 excluded. The suite counts itself and the plan does
not, so the suite wins. Quote `mix test`; never hand-type this number — that
drift has now happened to a law count, a migration count and two test counts in
this portfolio.

**What is live is the prior design.** The marketing page describes a
replay-gated, content-addressed registry. What is deployed predates that. The
portfolio nav carries `status: "live · prior design"` for exactly this reason:
"shipped" is true (it runs) and would be misread as "the replay-gated thing
ships". It does not.

## Quick start

```bash
mix deps.get
mix compile --warnings-as-errors
mix test                       # 112 tests, 2 excluded
mix format --check-formatted
mix phx.server
```

Deploy is `fly deploy` against `fly.toml` (app `fleetprompt`).

Check the deployed MCP endpoint:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  https://app.fleetprompt.com/mcp        # -> 200
```

## The specification is authoritative, and superseded in part

`docs/spec/README.md` is the technical specification and drives implementation.
It carries a supersession banner added 2026-08-15:

- **Superseded:** Supabase Auth as publisher identity, the shared `amp.profiles`
  table, and anything else resting on the shared-Supabase data layer, which was
  abandoned by ruling on **2026-07-30** in favour of `studbook`. studbook is a
  spec with no implementation, blocked on an unruled confidentiality question.
  **Do not build against it yet.**
- **Also corrected in the banner:** the spec describes WebHost.Systems as a
  **Convex** backend. It is not, and never was in this tree — WebHost depends on
  `@supabase/supabase-js` with no Convex dependency anywhere.
- **Not superseded:** the registry, trust, install and crystallizer design,
  which is the bulk of the document.

The spec was **not rewritten**. It is a dated design record and rewriting it
would fabricate a review nobody performed.

## A standing direction that affects this repository

Ruled 2026-08-15: **compute moves into the ComputeDriven OS, and the Fly.io apps
become storage or nothing.** This app is one of them. Nothing is torn down before
its OS-side replacement runs locally, but check `STACK_HUB.md` in the workspace
before planning new Fly-shaped work.

`fleet.*` in the archived Supabase instance still serves this product **today**,
which is precisely why that instance is archived rather than deleted.

## The portfolio nav

`amp-nav.js` is a **deployed copy**. The source is
`ampersand-nav/src/amp-nav.js`, fanned out by `sync-nav.sh`. Edits here are lost
on the next sync.

## Conventions

- `mix format`, warnings-as-errors.
- Never commit secrets.
- `old_scrap/` is historical and not authoritative.

## Related

- [computedriven.com](https://computedriven.com) — the discipline this is built under
- [specprompt.com](https://specprompt.com) — the content-addressed spec layer beside it
- [ampersandboxdesign.com](https://ampersandboxdesign.com) — the [&] Protocol
