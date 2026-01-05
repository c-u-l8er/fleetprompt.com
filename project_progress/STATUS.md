# FleetPrompt — Current Status

Last updated: 2026-01-05

## Executive summary

You now have a working split setup (Phoenix + Inertia backend, Svelte + Vite frontend), and Phase 1 backend foundations are in place:

- **Backend**: Phoenix app under `fleetprompt.com/backend`
- **Frontend**: Vite + Svelte app under `fleetprompt.com/frontend`
- **Integration**: Phoenix serves built assets from `backend/priv/static/assets`, and `/` renders an Inertia payload (`<div id="app" data-page="...">`).

**Phase 1 (Core Resources + Multi-tenancy) implementation is now in the codebase:**
- Ash domains added: `FleetPrompt.Accounts`, `FleetPrompt.Agents`, `FleetPrompt.Skills` (+ placeholders `FleetPrompt.Workflows`, `FleetPrompt.Packages` for later phases).
- Ash resources added:
  - `FleetPrompt.Accounts.Organization` (tenant schema management via `manage_tenant`)
  - `FleetPrompt.Accounts.User`
  - `FleetPrompt.Skills.Skill` (global)
  - `FleetPrompt.Agents.Agent` (multi-tenant via schema-per-tenant using `multitenancy :context`, state machine via `AshStateMachine`)
- Migrations generated and applied (including required Postgres extensions like `pgcrypto` and Ash SQL helper functions).
- AshAdmin (LiveView) is wired at `/admin` and is functional (LiveView socket mounted at `/live`).
- AshAdmin tenant selection UX is available at `/admin/tenant` (persists tenant in cookie + session; supports `demo` → `org_demo`) so you can browse tenant-scoped resources like Agents. The `/admin/tenant` header now matches the homepage header styling; the page uses the minimal controller layout to avoid a double-header with the Admin layout.
- UI/UX scaffolding (Inertia + Svelte) is in progress:
  - shared `AppShell` layout component
  - placeholder pages/routes: `/dashboard`, `/marketplace`, `/chat`
- Seeds script updated to create a demo org/user/skills and a tenant-scoped agent.

**Frontend note:** the Inertia client mounting code has been updated to mount using Inertia’s provided element (`setup({ el, ... })`) and to support both constructor-based and `mount(...)` based component styles. You still need to validate DOM rendering in the browser.

## Code map (backend `lib/` and frontend `src/`)

### Backend (`backend/lib`)
- `backend/lib/fleet_prompt/`
  - `application.ex` — OTP app boot (supervision tree)
  - `repo.ex` — `AshPostgres.Repo` and tenant discovery (`all_tenants/0`)
  - `accounts/` + `accounts.ex` — Accounts domain/resources (e.g. `Organization`, `User`)
  - `agents/` + `agents.ex` — Agents domain/resources (tenant-scoped `Agent`)
  - `skills/` + `skills.ex` — Skills domain/resources (global `Skill`)
  - `packages/` + `packages.ex` — Package domain placeholder (Phase 2+)
  - `workflows/` + `workflows.ex` — Workflow domain placeholder (Phase 3+)
- `backend/lib/fleet_prompt_web/`
  - `router.ex` — route + pipeline definitions (browser/admin; `/admin` + `/admin/tenant`)
  - `endpoint.ex` — Phoenix endpoint configuration
  - `controllers/` — controller actions + HEEx templates
    - `admin_tenant_controller.ex` + `admin_tenant_html/index.html.heex` — tenant selector UI
    - `page_controller.ex` — Inertia entry pages (`/`, `/dashboard`)
    - `marketplace_controller.ex`, `chat_controller.ex` — scaffold routes
  - `components/layouts/`
    - `root.html.heex` — root HTML shell + asset tags + inertia head/title
    - `admin.html.heex` — AshAdmin chrome (header + tenant context banner)
    - `inertia.html.heex` — minimal layout for Inertia pages (no chrome)

### Frontend (`frontend/src`)
- `frontend/src/app.ts` — Inertia + Svelte client bootstrap
- `frontend/src/app.css` — global styles
- `frontend/src/lib/components/AppShell.svelte` — shared app chrome (homepage-style header + page header block)
- `frontend/src/pages/` — Inertia page components
  - `Home.svelte` — homepage content (uses `AppShell`)
  - `Dashboard.svelte` — dashboard scaffold page (uses `AppShell`)
  - `Marketplace.svelte` — marketplace scaffold page (uses `AppShell`)
  - `Chat.svelte` — chat scaffold page (uses `AppShell`)
- `frontend/src/types/` — shared TS types (as needed)

---

## What works (confirmed)

### Backend
- `mix phx.server` starts and serves at `http://127.0.0.1:4000`.
- `/` is handled by `FleetPromptWeb.PageController.home/2` and renders an Inertia response.
- The HTML source for `/` includes:
  - `<script type="module" src="/assets/app.js"></script>`
  - `<link rel="stylesheet" href="/assets/app.css">`
  - `<div id="app" data-page="...json..."></div>` (valid JSON payload)
- Ash resources/domains compile and migrations have been generated + applied via `mix ash_postgres.generate_migrations` and `mix ash_postgres.migrate`.
- AshAdmin is available at `http://127.0.0.1:4000/admin`.
- Tenant selector is available at `http://127.0.0.1:4000/admin/tenant` (choose `demo` / `org_demo` to browse tenant-scoped resources like `Agents`). The page header matches the homepage header styling and does not overlap with the Admin layout header (layout is overridden to the minimal Inertia layout for this controller).

### Frontend build pipeline
- Frontend builds successfully with Vite (pinned to v5 to satisfy peer deps) and outputs:
  - `backend/priv/static/assets/app.js`
  - `backend/priv/static/assets/app.css`
- Phoenix dev watcher is running `vite build --watch` (i.e., auto rebuild on save; not HMR).

### Inertia boot (client)
Using `/?fp_debug=1` on Phoenix (`:4000`) confirms:
- frontend bundle loads
- `#app[data-page]` is found
- Inertia `setup()` runs with expected props:
  - `initialPage`
  - `initialComponent`
  - `resolveComponent`

### Phase 1 verification (local)
- Core resources exist in code: `Organization`, `User`, `Skill`, `Agent` (tenant-scoped).
- Tenant migration(s) exist for `agents` tables in tenant schemas.
- Seeds create:
  - public data: organizations/users/skills
  - tenant data: `org_demo.agents`
- AshAdmin tenant selection UX exists at `/admin/tenant` to select `org_demo` before browsing tenant-scoped resources in `/admin`.
- Multi-tenancy smoke tests exist and pass (`Agent` creation in tenant context + state transition).
- Test environment is configured to avoid running background Oban queues/plugins during tests (prevents DB sandbox ownership issues).

---

## What is blocked / not yet working

### Validate UI renders into `#app` after the Inertia mount fix
The Inertia client now uses a more compatible mounting strategy (uses `setup({ el, ... })`’s mount element and falls back between `new App(...)` and `mount(...)`).

How to validate:
- Visit Phoenix at `http://127.0.0.1:4000/?fp_debug=1`
- In the browser console, confirm you see:
  - `"[FleetPrompt] Inertia setup()"` log
  - `"[FleetPrompt] Inertia mounted"` log, including:
    - `mountedWith: "new"` or `mountedWith: "mount"`
    - `targetChildren` should be `> 0`
- Visually confirm the Home page content appears (e.g., “Welcome to FleetPrompt” and the CTA buttons)

If `targetChildren` is still `0` after `"[FleetPrompt] Inertia mounted"`:
- confirm the server response contains `<div id="app" data-page="...">` (valid JSON)
- confirm `resolve("Home")` is actually finding `./pages/Home.svelte`
- confirm the page component isn’t rendering an empty fragment (e.g., unexpected conditional rendering)

---

## Known issues / warnings (non-blocking)

### Live reload
- Phoenix warns about `inotify-tools` missing. This disables LiveReload file watching only.
- Not a production issue.

### Dev workflow confusion
- `http://localhost:5173` is the Vite dev server. It will show `<div id="app"></div>` with **no** Inertia `data-page`.
- The correct URL for Inertia is **Phoenix**: `http://127.0.0.1:4000/`.

### Dev asset mode
- Phoenix runs `vite build --watch`, which is rebuild-on-save, not HMR.
- If you want HMR, we’ll need a different integration (proxy / load assets from Vite dev server while still rendering the Inertia payload from Phoenix).

---

## Next concrete steps (in order)

### 1) Validate the Inertia DOM render in the browser (highest priority)
Goal: after loading `/`, `#app` should contain rendered markup for the Home page.

Concrete checks to perform:
- Load `http://127.0.0.1:4000/?fp_debug=1`
- Confirm `"[FleetPrompt] Inertia mounted"` appears in console and indicates:
  - `mountedWith` is `"new"` or `"mount"`
  - `targetChildren > 0`
- Visually confirm the Home page renders (“Welcome to FleetPrompt”, CTA buttons)

Exit criteria:
- Home page DOM appears
- `#app.children.length > 0`
- Debug log shows a successful mount (`mountedWith` + `targetChildren`)
- No runtime errors

### 2) Phase 1: run seeds and verify AshAdmin + tenant behavior
Goal: confirm Phase 1 resources work end-to-end locally.

Concrete checks to perform:
- Run `mix run priv/repo/seeds.exs`
- Visit `http://127.0.0.1:4000/admin/tenant` and select `demo` (or `org_demo`)
- Visit `http://127.0.0.1:4000/admin` and confirm you can browse:
  - Organizations (and tenant schema management is working)
  - Users
  - Skills
  - Agents (tenant-scoped; visible after selecting a tenant)
- Visit the UI scaffold routes to validate navigation + layout:
  - `http://127.0.0.1:4000/dashboard`
  - `http://127.0.0.1:4000/marketplace`
  - `http://127.0.0.1:4000/chat`
- Run `mix test` and confirm the multi-tenancy agent tests pass.

Exit criteria:
- Admin tenant selector loads at `/admin/tenant`
- Admin UI loads at `/admin`
- Seed data creates demo org/user/skills and a tenant-scoped agent
- Tenant-scoped Agents are browsable in AshAdmin after selecting a tenant
- Tests pass

### 3) Phase 2: Package system + marketplace
After Phase 1 verification:
- Implement package resources + installer job and marketplace controllers/pages from the Phase 2 doc.

### 4) Optional: upgrade dev ergonomics (HMR)
If desired:
- Run Vite `dev` and load assets from `:5173` in Phoenix layout in dev only, while still using Phoenix for HTML and Inertia payload.
- This makes UI iteration much faster.

---

## How to run (current)

### Backend (Phoenix)
1. Ensure Postgres is running.
2. Create DB and run migrations:
   - `mix ecto.create`
   - `mix ecto.migrate`
3. Start server:
   - `mix phx.server`
4. Visit:
   - `http://127.0.0.1:4000/`
   - Debug: `http://127.0.0.1:4000/?fp_debug=1`

### Frontend (Vite build)
- Build once:
  - `npm run build` in `fleetprompt.com/frontend`
- Rebuild-on-save (already via Phoenix watcher):
  - `vite build --watch`

---

## Notes for contributors

- Do not validate Inertia behavior on `http://localhost:5173/`. That environment does not include the server-rendered Inertia `data-page`.
- Keep `vite` pinned to v5 unless you also update `@sveltejs/vite-plugin-svelte` to a version compatible with v6.