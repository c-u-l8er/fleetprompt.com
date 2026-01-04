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
- Phoenix watcher working directory:
  - corrected Vite watcher `cd:` so Phoenix can run `vite build --watch` without crashing.
- Inertia mount/runtime issues:
  - resolved “Cannot read properties of null (reading 'component')” by ensuring a valid Inertia page payload and correct `render_inertia` usage.
  - resolved “Cannot use 'in' operator to search for 'Symbol($state)' in undefined” by fixing the Inertia Svelte resolver to return the page module’s `default` export and using a compatible mount strategy.
- Oban runtime failures:
  - fixed repeated `relation "public.oban_jobs" does not exist` by adding and running the Oban migration.
- Phoenix CodeReloader warning:
  - restored Mix project listener configuration required by code reloader (`listeners: [Phoenix.CodeReloader]`).

### Notes / Operational
- Development environment may warn about missing `inotify-tools` (optional; impacts live reload only).
- PostgreSQL must be running locally for the backend to boot cleanly (Repo + Oban depend on it).
- If you browse the Vite dev server (`:5173`) directly, it will not include `data-page` and therefore won’t behave like the Phoenix-rendered Inertia page. The intended dev entrypoint is Phoenix (`:4000`) with Vite building into `priv/static/assets`.

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