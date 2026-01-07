# Changelog

All notable changes to this repository’s implementation work (setup, architecture decisions, and debugging milestones) will be documented here.

This project is early-stage and is being built iteratively from the phase docs in `fleetprompt.com/docs`.

## [Unreleased]

### Added
- Split repo layout:
  - Backend Phoenix app under `fleetprompt.com/backend`
  - Frontend Vite + Svelte app under `fleetprompt.com/frontend`
- Initial Phoenix + Inertia wiring (server-driven SPA via Inertia rather than LiveView).
- Frontend Vite build output targeting Phoenix static assets directory.
- Oban database migration to create `oban_jobs` / `oban_peers` tables (via `Oban.Migration.up/1`).
- Frontend bootstrap hardening:
  - only mount when `#app[data-page]` is present
  - explicit parsing of Inertia `data-page` JSON to avoid undefined initialPage edge cases
  - optional debug logging gated by `?fp_debug=1`
- Phase 1 core resources (Ash):
  - Ash domains: `FleetPrompt.Accounts`, `FleetPrompt.Agents`, `FleetPrompt.Skills` (plus placeholder domains for `FleetPrompt.Workflows` and `FleetPrompt.Packages` to satisfy `:ash_domains` config).
  - Resources: `FleetPrompt.Accounts.Organization`, `FleetPrompt.Accounts.User`, `FleetPrompt.Agents.Agent` (tenant-scoped), `FleetPrompt.Skills.Skill`.
  - Multi-tenancy foundation:
    - `Organization` configured with `manage_tenant` schema creation using `org_<slug>` template.
    - Repo updated to `AshPostgres.Repo` and `all_tenants/0` implemented (with bootstrap-safe fallback).
- Phase 1 migrations and seeds:
  - Generated AshPostgres migrations for core resources, including tenant migrations for `agents`.
  - Generated/installed required Postgres extensions and Ash SQL helper functions (`pgcrypto`, `ash-functions`, etc.).
  - Seed script updated to create demo organization/user/skills and a tenant-scoped demo agent via `Ash.Changeset.set_tenant/2`.
- Phase 1 admin and tests:
  - Added `AshAdmin` UI mounted at `/admin`.
  - Added admin tenant selector UI at `/admin/tenant` to choose the active tenant schema for tenant-scoped resources.
  - Improved tenant selector UX:
    - moved from an inline string-built HTML response to a proper HEEx template (`FleetPromptWeb.AdminTenantHTML`)
    - added Tailwind styling consistent with the app design
    - supports `GET /admin/tenant?tenant=...` as a convenience action (sets tenant then redirects back)
  - Added `FleetPromptWeb.Plugs.AdminTenant` to persist/normalize `tenant` (supports `?tenant=demo` -> `org_demo`) for AshAdmin sessions.
  - Added an Admin controller layout (`Layouts.admin`) with a visible “Tenant context” banner and quick links (`/admin`, `/admin/tenant`, app routes).
  - Added a minimal Inertia controller layout (`Layouts.inertia`) so Inertia pages don’t get extra server-rendered chrome.
  - Added multi-tenancy smoke tests for tenant-scoped agent creation and state transitions.
  - Disabled running Oban queues/plugins during tests to avoid SQL sandbox ownership issues.
- UI/UX scaffolding (Inertia):
  - Added shared Svelte layout component `AppShell`.
  - Added placeholder Inertia pages: `Dashboard`, `Marketplace`, `Chat`.
  - Added backend routes and controller actions for `/dashboard`, `/marketplace`, `/chat`.
  - Phase 2 marketplace install mechanics (tenant-scoped, now Phase 2B-aligned):
    - Added `FleetPrompt.Packages.Installation` (tenant-scoped) to track package install lifecycle, status, and idempotency key.
    - Added `FleetPrompt.Jobs.PackageInstaller` (Oban worker) to install package-defined content into the tenant schema (agents now; workflows/skills stubbed).
    - Realigned installs to be **directive-driven** (Phase 2B):
      - Added Signals + Directives foundations:
        - Added Ash domains: `FleetPrompt.Signals` and `FleetPrompt.Directives`.
        - Added tenant-scoped resources: `FleetPrompt.Signals.Signal` and `FleetPrompt.Directives.Directive`.
        - Added tenant migration to create `signals` and `directives` tables (`backend/priv/repo/tenant_migrations/..._add_signals_and_directives.exs`).
      - Added durable plumbing:
        - Added `FleetPrompt.Signals.SignalBus` (best-effort idempotent signal emission via `dedupe_key`).
        - Added `FleetPrompt.Jobs.SignalFanout` (Oban fanout to configured handlers).
        - Added `FleetPrompt.Signals.Replay` (re-enqueue fanout jobs for persisted signals).
        - Added `FleetPrompt.Jobs.DirectiveRunner` (Oban runner; v1 supports `package.install`).
    - Updated `POST /marketplace/install` endpoint:
      - creates/uses a tenant-scoped `Installation`,
      - creates/uses a tenant-scoped `Directive` named `package.install`,
      - enqueues `DirectiveRunner`, which enqueues `PackageInstaller` to do the tenant writes.
    - Added tenant migration for `package_installations` in `backend/priv/repo/tenant_migrations`.
    - Updated `PackageInstaller` to emit best-effort install lifecycle signals and attempt to mark the matching directive succeeded/failed.
    - Added `FleetPrompt.Packages.PackageInstallerTest` to validate the installer behavior (installs agents into tenant, retry-safe/idempotent-ish, and failure modes update installation status).
  - Added Forums UX scaffold (Phase 6 foundation; mocked UI for now):
    - Added backend routes: `/forums`, `/forums/new`, `/forums/c/:slug`, `/forums/t/:id` (authenticated).
    - Added `FleetPromptWeb.ForumsController` to render forum Inertia pages with mocked props.
    - Added Inertia pages: `Forums`, `ForumsNew`, `ForumsCategory`, `ForumsThread`.
    - Added a “Forums” link in the primary app navigation (after Dashboard, before Marketplace).
- Authentication + org context (multi-org):
  - Added session-based auth endpoints and Inertia pages:
    - routes: `GET /login`, `POST /login`, `DELETE /logout`
    - Inertia pages: `Login.svelte`, `Register.svelte`
  - Added self-serve registration flow to create an Organization + first owner user:
    - routes: `GET /register`, `POST /register`
    - creates org tenant schema (`org_<slug>`) via `manage_tenant`
  - Added multi-org membership model:
    - new Ash resource: `FleetPrompt.Accounts.OrganizationMembership` (user_id, organization_id, role, status)
    - new DB migration to create `organization_memberships` with unique (org_id, user_id)
  - Added org/tenant switching:
    - route: `POST /org/select` to switch current org (membership-gated)
    - header org switcher UI in `AppShell` (dropdown when multiple orgs available)
  - Added org-scoped admin authorization:
    - restrict `/admin` shell and `/admin/ui` (AshAdmin LiveView) to membership roles `:owner`/`:admin`
    - allow `/admin/tenant` for authenticated users, but restrict tenant choices to admin-eligible orgs

### Changed
- Backend asset pipeline:
  - replaced Phoenix esbuild/tailwind tooling with split-frontend `vite build --watch` invoked via Phoenix watchers.
- Controller action for `/` now renders via `render_inertia/3` with a direct props map.
- Root layout switched to Inertia helpers:
  - `<.inertia_title>` and `<.inertia_head content={@inertia_head} />`
  - module script load for `/assets/app.js`
- Layout component expectations:
  - `Layouts.app/1` changed from `slot :inner_block` usage to controller layout usage with `inner_content`,
    fixing KeyError crashes when rendering via `layouts: [html: FleetPromptWeb.Layouts]`.

### Fixed
- Frontend dependency resolution:
  - resolved npm peer dependency conflict by aligning `vite` to the peer range required by `@sveltejs/vite-plugin-svelte`.
- App navigation highlighting:
  - fixed `AppShell` active-link styling to stay in sync after Inertia client-side navigation (listen to Inertia navigation events).
- Phoenix watcher working directory:
  - corrected Vite watcher `cd:` so Phoenix can run `vite build --watch` without crashing.
- Inertia mount/runtime issues:
  - resolved “Cannot read properties of null (reading 'component')” by ensuring a valid Inertia page payload and correct `render_inertia` usage.
  - resolved “Cannot use 'in' operator to search for 'Symbol($state)' in undefined” by fixing the Inertia Svelte resolver to return the page module’s `default` export and using a compatible mount strategy.
  - fixed missing DOM render into `#app` by mounting via Inertia’s provided `el` and supporting both constructor-based Svelte components (`new App({ target, props })`) and function components (`mount(App, { target, props })`).
- AshAdmin LiveView wiring:
  - added LiveView signing salt configuration and mounted the LiveView websocket endpoint at `/live` so AshAdmin can connect.
- Admin tenant selector UI/layout:
  - updated `/admin/tenant` to match the homepage header styling
  - avoided double headers by overriding `AdminTenantController` to use the minimal controller layout (instead of `Layouts.admin`)
- Oban runtime failures:
  - fixed repeated `relation "public.oban_jobs" does not exist` by adding and running the Oban migration.
- Phoenix CodeReloader warning:
  - restored Mix project listener configuration required by code reloader (`listeners: [Phoenix.CodeReloader]`).
- Auth + Inertia request handling:
  - fixed `Phoenix.NotAcceptableError` during login by aligning request headers with the browser pipeline (`accepts: ["html"]`).
- Ash query DSL usage:
  - fixed compilation/runtime issues by requiring Ash query macros where needed and using `Ash.Expr.expr/1` for filters.
- Flash notifications:
  - updated flash rendering to use app-native Tailwind classes (not daisyUI), fixing toasts appearing at the bottom of the page.
- Tenant migration + registration hardening:
  - made tenant migration safer by using schema-qualified UUID defaults (`public.gen_random_uuid()`), and making tenant table creation idempotent.
  - improved registration error logging and responses to surface tenant/migration issues.
  - added orphaned-tenant-schema cleanup logic during registration to prevent `schema_migrations_pkey` conflicts when `org_<slug>` exists without a matching `organizations` row.

### Notes / Operational
- Development environment may warn about missing `inotify-tools` (optional; impacts live reload only).
- PostgreSQL must be running locally for the backend to boot cleanly (Repo + Oban depend on it).
- If you browse the Vite dev server (`:5173`) directly, it will not include `data-page` and therefore won’t behave like the Phoenix-rendered Inertia page. The intended dev entrypoint is Phoenix (`:4000`) with Vite building into `priv/static/assets`.
- If registration fails mid-flight, you may end up with an orphaned tenant schema (`org_<slug>`) in dev. The registration flow now attempts to detect/clean these up, but manual cleanup may still be required in edge cases.

---

## [2026-01-04] Bootstrap & Integration Milestones

### Architecture decisions
- Chose **Inertia + Svelte** (not LiveView) as the primary UI architecture.
- Implemented a **split frontend/backend** structure to keep Node toolchain isolated from the Phoenix app.

### Milestones completed
- Phoenix app scaffolding and dependency alignment (Inertia, Ash, Oban, Req/Finch, etc.).
- Vite build integration with Phoenix static assets and watcher setup.
- Inertia server-side layout integration and client bootstrap stabilization.
- Oban schema migration added and validated as required for runtime.

---