# FleetPrompt — Current Status

Last updated: 2026-01-08

## Executive summary

You now have a working split setup (Phoenix + Inertia backend, Svelte + Vite frontend), and Phase 1 backend foundations are in place — **plus** end-to-end **session auth + org membership + org/tenant selection** — **plus** Phase 2A package installs — **plus** Phase 2B platform primitives — and you have begun Phase 2C (Forums lighthouse) wiring:

- **Signals** (tenant-scoped persisted events) + a minimal Signal fanout/replay mechanism
- **Directives** (tenant-scoped persisted commands) + a Directive runner (Oban) to execute side effects audibly
- **Forums (Phase 2C thin slice, in progress but usable):**
  - tenant-scoped Ash resources: Categories/Threads/Posts
  - tenant migration adds `forum_categories`, `forum_threads`, `forum_posts`
  - routes and UI now support creating categories, threads, and replies
  - forum writes emit Signals (`forum.category.created`, `forum.thread.created`, `forum.post.created`)
  - thread view includes a minimal **audit trail** UI sourced from tenant Signals (best-effort)
  - create flows have explicit prerequisites (enforced server-side; UX gated client-side):
    - must be signed in
    - must have a selected tenant (`tenant_schema` is required for writes)
    - categories must exist for the tenant to create a thread
    - archived categories should not accept new threads
  - forum create pages include an optional debug panel (append `?fp_debug=1`) to show live state:
    - `tenant_schema`, current input values, `validationErrors`, `canSubmit`

Most importantly, the Marketplace install path has been realigned so installs are requested via **Directives** (auditable intent), and executed by the **DirectiveRunner**, which then enqueues the existing `PackageInstaller`.

- **Backend**: Phoenix app under `fleetprompt.com/backend`
- **Frontend**: Vite + Svelte app under `fleetprompt.com/frontend`
- **Integration**: Phoenix serves built assets from `backend/priv/static/assets`, and routes render Inertia payloads (`<div id="app" data-page="...">`).

**Core foundation (Ash + multi-tenancy):**
- Ash domains: `FleetPrompt.Accounts`, `FleetPrompt.Agents`, `FleetPrompt.Skills` (+ placeholders `FleetPrompt.Workflows` and `FleetPrompt.Packages`).
- Resources:
  - `FleetPrompt.Accounts.Organization` (schema-per-tenant via `manage_tenant`)
  - `FleetPrompt.Accounts.User`
  - `FleetPrompt.Accounts.OrganizationMembership` (multi-org membership + per-org roles)
  - `FleetPrompt.Skills.Skill` (global)
  - `FleetPrompt.Agents.Agent` (tenant-scoped, `multitenancy :context`, state machine via `AshStateMachine`)
- Platform primitives (Phase 2B foundation now present in code):
  - `FleetPrompt.Signals.Signal` (tenant-scoped persisted events / immutable facts)
  - `FleetPrompt.Directives.Directive` (tenant-scoped persisted commands / controlled intent)
  - `FleetPrompt.Signals.SignalBus` (idempotent-ish signal emission by `dedupe_key`)
  - `FleetPrompt.Jobs.SignalFanout` (durable fanout to configured handlers)
  - `FleetPrompt.Signals.Replay` (re-enqueue fanout jobs for persisted signals)
  - `FleetPrompt.Jobs.DirectiveRunner` (executes directives; v1 supports `package.install`)
- Package marketplace (Phase 2A thin-slice, now Phase 2B-aligned):
  - `FleetPrompt.Packages.Package` + `FleetPrompt.Packages.Review` (public schema)
  - `FleetPrompt.Packages.Installation` (tenant-scoped, `multitenancy :context`)
  - `POST /marketplace/install` now creates/uses:
    - a tenant-scoped `Installation` record (state/progress)
    - a tenant-scoped `Directive` (`package.install`) (auditable intent)
    - enqueues `DirectiveRunner`, which enqueues `PackageInstaller` to do the actual tenant writes
  - `FleetPrompt.Jobs.PackageInstaller` now emits best-effort install lifecycle signals and attempts to mark the matching directive succeeded/failed (see “Known gaps” below).
- Tenant migrations exist for tenant-scoped resources (`org_<slug>` schemas). Agents tenant migrations are hardened for UUID default resolution/idempotency, and tenant migrations exist for:
  - `package_installations`
  - `signals` + `directives`
  - `forum_categories` + `forum_threads` + `forum_posts` (Forums lighthouse)

**Auth + org access control (new):**
- Session-based auth endpoints:
  - `GET /login`, `POST /login`, `DELETE /logout`
  - `GET /register`, `POST /register` (creates org + owner user + membership; logs user in)
- Membership-gated org selection:
  - `POST /org/select` switches current org/tenant for the signed-in user.
- Authorization model:
  - org membership roles: `:owner | :admin | :member`
  - admin UI surfaces (`/admin`, `/admin/ui`) restricted to org roles `:owner/:admin`
  - tenant/org selection constrained to organizations the user is allowed to access

**UI/UX scaffolding (Inertia + Svelte) is in progress:**
- Shared `AppShell` provides consistent header/nav.
- Header now supports:
  - current user display + sign out
  - organization dropdown (when user belongs to multiple orgs)
  - tenant badge (derived from selected org)
- Primary nav now includes: `Dashboard` → `Forums` → `Marketplace` → `Chat`
- Inertia pages: `Home`, `Dashboard`, `Forums`, `ForumsNew`, `ForumsCategory`, `ForumsThread`, `Marketplace`, `Chat`, `Login`, `Register`, `ForumsCategoryNew`
- Navigation UX fix:
  - `AppShell` active-link styling stays in sync after Inertia client-side navigation.
- Seeds updated to ensure demo admin has an owner membership in the demo org.

**Frontend note:** the frontend is in the middle of a Svelte 5 migration; Pages are being converted to runes mode to avoid form validation/reactivity issues under Inertia.

For the Forums create flows specifically (`/forums/categories/new`, `/forums/new`):
- If submit appears stuck/disabled, ensure you’re loading the latest built assets (hard refresh; restart the dev watcher if needed).
- Use `?fp_debug=1` on those pages to confirm `tenant_schema`, field values, `validationErrors`, and `canSubmit` match what you expect.

## Code map (backend `lib/` and frontend `src/`)

### Backend (`backend/lib`)
- `backend/lib/fleet_prompt/`
  - `application.ex` — OTP app boot (supervision tree)
  - `repo.ex` — `AshPostgres.Repo` and tenant discovery (`all_tenants/0`)
  - `accounts/` + `accounts.ex` — Accounts domain/resources
    - `accounts/organization.ex` — `Organization` (schema-per-tenant via `manage_tenant`)
    - `accounts/user.ex` — `User` (public schema)
    - `accounts/organization_membership.ex` — `OrganizationMembership` (multi-org membership + per-org role/status)
    - `accounts/auth.ex` — auth helpers (email/password verification against Ash users)
  - `agents/` + `agents.ex` — Agents domain/resources (tenant-scoped `Agent`)
  - `skills/` + `skills.ex` — Skills domain/resources (global `Skill`)
  - `packages/` + `packages.ex` — Packages domain (Phase 2A): `Package` + `Review` (public) and `Installation` (tenant-scoped)
  - `jobs/package_installer.ex` — Oban worker to apply package installs into tenant schemas (Phase 2A thin-slice)
  - `workflows/` + `workflows.ex` — Workflow domain placeholder (Phase 3+)
- `backend/lib/fleet_prompt_web/`
  - `router.ex` — route + pipeline definitions
    - browser: Inertia routes + auth + org context
    - protected: requires session auth
    - admin: authenticated baseline + org context
    - admin_org_admin: restricts admin UI to org roles `:owner/:admin`
  - `endpoint.ex` — Phoenix endpoint configuration
  - `inertia_helpers.ex` — shared Inertia props merge (user, org list, current org, tenant context, request path)
  - `plugs/`
    - `fetch_current_user.ex` — loads `current_user` (and org load for convenience)
    - `fetch_org_context.ex` — membership-gated org selection + sets tenant cookie/session + assigns `:ash_tenant`
    - `require_auth.ex` — protects routes, Inertia-safe redirects
    - `require_org_admin.ex` — restricts admin UI to membership roles `:owner/:admin`
    - `admin_tenant.ex` — keeps Ash tenant consistent; ignores unsafe tenant overrides when a user/org context exists
  - `controllers/`
    - `auth_controller.ex` — `GET/POST /login`, `DELETE /logout`, `GET/POST /register`
    - `org_controller.ex` — `POST /org/select` (switch org/tenant; membership-gated)
    - `admin_tenant_controller.ex` + `admin_tenant_html/index.html.heex` — org/tenant selector UI (restricted to org-admin memberships)
    - `page_controller.ex` — Inertia entry pages (`/`, `/dashboard`)
    - `marketplace_controller.ex`, `chat_controller.ex` — scaffold routes (render via shared inertia helper)
    - `forums_controller.ex` — Forums lighthouse (Phase 2C) controller with real tenant wiring:
      - reads: `/forums`, `/forums/c/:slug`, `/forums/t/:id`
      - creates: `POST /forums/categories`, `POST /forums/threads`, `POST /forums/t/:id/replies`
      - emits Signals for creates (`forum.category.created`, `forum.thread.created`, `forum.post.created`)
      - thread view includes a minimal audit trail prop (`audit_events`) sourced from tenant Signals
  - `components/layouts/`
    - `root.html.heex` — root HTML shell + asset tags + inertia head/title
    - `admin.html.heex` — AshAdmin chrome (admin header + context banner)
    - `inertia.html.heex` — minimal layout for Inertia pages (no chrome)
  - `components/core_components.ex`
    - flash/toast rendering updated to avoid DaisyUI dependency (fixed positioning + dismiss button)

### Frontend (`frontend/src`)
- `frontend/src/app.ts` — Inertia + Svelte client bootstrap
- `frontend/src/app.css` — global styles
- `frontend/src/lib/components/AppShell.svelte` — shared app chrome
  - shows current user + sign out
  - shows org dropdown when multiple orgs are available
  - posts `POST /org/select` to switch org/tenant
- `frontend/src/pages/` — Inertia page components
  - `Home.svelte`
  - `Dashboard.svelte`
  - `Forums.svelte` — forums index (mocked UI; Phase 6 foundation)
  - `ForumsNew.svelte` — new thread form (mocked UI; Phase 6 foundation)
  - `ForumsCategory.svelte` — category view (mocked UI; Phase 6 foundation)
  - `ForumsThread.svelte` — thread view (mocked UI; Phase 6 foundation)
  - `Marketplace.svelte`
  - `Chat.svelte`
  - `Login.svelte` — session sign-in UI
  - `Register.svelte` — create org + owner user UI
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
  - `http://127.0.0.1:4000/forums`
  - `http://127.0.0.1:4000/marketplace`
  - `http://127.0.0.1:4000/chat`
- Run `mix test` and confirm the multi-tenancy agent tests pass.

Exit criteria:
- Admin tenant selector loads at `/admin/tenant`
- Admin UI loads at `/admin`
- Seed data creates demo org/user/skills and a tenant-scoped agent
- Tenant-scoped Agents are browsable in AshAdmin after selecting a tenant
- Tests pass

### 3) Phase 2B (MVP): apply tenant migrations for Signals + Directives
Goal: make Phase 2B primitives *actually usable* per-tenant.

Concrete checks to perform:
- Run tenant migrations (so `org_<slug>` schemas have `signals` and `directives` tables).
- In AshAdmin (after selecting a tenant), confirm you can browse:
  - Signals (tenant-scoped)
  - Directives (tenant-scoped)

Exit criteria:
- `signals` table exists in tenant schema(s)
- `directives` table exists in tenant schema(s)
- AshAdmin can list Signals/Directives in the selected tenant without errors

### 4) Phase 2A → 2B-aligned install loop: prove Marketplace install is directive-driven
Now that the Marketplace install flow is routed through directives, verify the loop end-to-end:

- Apply tenant migrations (ensure tenant has `package_installations`, `directives`, and `signals`).
- Verify `POST /marketplace/install`:
  - creates (or re-uses) a tenant-scoped `Installation`,
  - creates (or re-uses) a tenant-scoped `Directive` named `package.install`,
  - enqueues `DirectiveRunner`.
- Verify `DirectiveRunner` enqueues `PackageInstaller`, and the package includes are installed into the tenant (agents now).
- Verify Signals are emitted (best-effort) for:
  - `package.install.requested` (from Marketplace)
  - `package.installation.*` lifecycle (from PackageInstaller)

Exit criteria:
- A Marketplace install results in a persisted Directive + Installation for the tenant
- Directive transitions to `running` then `succeeded` (or `failed` with error)
- Installation transitions to `installed` (or `failed` with error)
- Tenant Signals show at least one install-related signal

### 5) Known gaps to close next (small but important)
- Directive ↔ installation linkage now uses a shared `idempotency_key` (Marketplace sets the same key on both the tenant `Installation` record and the `package.install` directive), so `PackageInstaller` can reliably mark the directive succeeded/failed.

### 6) Optional: upgrade dev ergonomics (HMR)
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