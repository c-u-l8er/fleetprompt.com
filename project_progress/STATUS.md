# FleetPrompt — Current Status

Last updated: 2026-01-04

## Executive summary

You now have a working split setup:

- **Backend**: Phoenix app under `fleetprompt.com/backend`
- **Frontend**: Vite + Svelte app under `fleetprompt.com/frontend`
- **Integration**: Phoenix serves built assets from `backend/priv/static/assets`, and the `/` route renders an **Inertia page payload** (`<div id="app" data-page="...">`) that the frontend successfully boots and reaches Inertia `setup()`.

The remaining gap is **actual DOM rendering into `#app`** (Svelte mount results in `#app.children.length === 0` even though boot and setup run). There are no console errors right now, so the next work should focus on verifying the Svelte/Inertia root component is mounting as expected and whether the adapter is targeting the correct element.

---

## What works (confirmed)

### Backend
- `mix phx.server` starts and serves at `http://127.0.0.1:4000`.
- `/` is handled by `FleetPromptWeb.PageController.home/2` and renders an Inertia response.
- The HTML source for `/` includes:
  - `<script type="module" src="/assets/app.js"></script>`
  - `<link rel="stylesheet" href="/assets/app.css">`
  - `<div id="app" data-page="...json..."></div>` (valid JSON payload)

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

---

## What is blocked / not yet working

### UI does not render into `#app`
On Phoenix (`:4000`), `document.querySelector("#app")?.children?.length` remains `0` after boot and setup. This means:

- the Inertia + Svelte root is not producing DOM nodes, or
- it mounts somewhere unexpected, or
- the adapter `setup`/mount call is not correct for the version combination, or
- the root component renders an empty fragment due to component/layout wiring.

This is the **current primary blocker**.

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

### 1) Fix the missing DOM render into `#app` (highest priority)
Goal: after loading `/`, `#app` should contain rendered markup for the Home page.

Concrete checks to perform:
- Confirm `mount()` is targeting the exact `HTMLElement` returned by `document.querySelector("#app[data-page]")`.
- Confirm the resolved page component returned by `resolve("Home")` is the Svelte component default export (not the module wrapper).
- Confirm the Home page component is receiving the `message` prop and generating DOM (not throwing internally).
- Add a temporary visible “smoke test” render (e.g., render a static text node before boot) to verify `#app` can be mutated.

Exit criteria:
- Home page DOM appears
- `#app.children.length > 0`
- No runtime errors

### 2) Normalize repo structure
There were earlier “nested” paths created during scaffolding (e.g., `backend/fleet_prompt/...`) that should not be treated as the canonical backend. Canonical paths should be:
- Backend: `fleetprompt.com/backend`
- Frontend: `fleetprompt.com/frontend`

Exit criteria:
- Only one backend app is considered “active”
- Build outputs match the active backend’s `priv/static/assets`

### 3) Phase 1 start: Ash resources + multi-tenancy
Once the UI mounts, proceed with:
- Ash domain modules + resources from `docs/phase_1_core_resources.md`
- Repo multi-tenancy configuration
- migrations + seeds
- minimal pages/routes to exercise resources

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