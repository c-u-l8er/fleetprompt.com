<script lang="ts">
  import { inertia } from "@inertiajs/svelte";
  import AppShell from "../lib/components/AppShell.svelte";

  /**
   * Placeholder props (safe defaults).
   * Later (Phase 2) the backend will provide real `packages`, `featured`, and `filters`.
   */
  export let title: string = "Marketplace";
  export let subtitle: string =
    "Browse installable packages (agents, workflows, skills). Coming soon.";
</script>

<svelte:head>
  <title>{title} • FleetPrompt</title>
</svelte:head>

<AppShell {title} {subtitle} showAdminLink={true}>
  <svelte:fragment slot="header-actions">
    <a
      use:inertia
      href="/dashboard"
      class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
    >
      Dashboard
    </a>

    <a
      href="/admin/tenant"
      class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
      title="AshAdmin runs on LiveView; tenant selection is required to browse tenant-scoped resources."
    >
      Admin
    </a>
  </svelte:fragment>

  <section class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8">
    <div class="max-w-3xl">
      <h2 class="text-2xl sm:text-3xl font-semibold tracking-tight">
        Marketplace (placeholder)
      </h2>
      <p class="mt-3 text-sm sm:text-base text-muted-foreground">
        This page is a UI scaffold. Next we’ll implement the Package resources, Marketplace controller,
        and install flow (Phase 2). For now, use AshAdmin to browse seeded resources.
      </p>

      <div class="mt-6 flex flex-wrap items-center gap-3">
        <a
          href="/admin/tenant"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-10 px-4"
        >
          Select tenant (recommended)
        </a>

        <a
          href="/admin"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-10 px-4"
        >
          Open AshAdmin
        </a>

        <a
          use:inertia
          href="/chat"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-10 px-4"
        >
          Go to Chat
        </a>
      </div>
    </div>
  </section>

  <section class="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-6">
    <div class="lg:col-span-2 rounded-2xl border border-border bg-card text-card-foreground p-6">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h3 class="font-semibold">Search packages</h3>
          <p class="mt-1 text-sm text-muted-foreground">
            Search, filters, and featured sections will be wired once the package system exists.
          </p>
        </div>
        <span class="text-xs text-muted-foreground rounded-full border border-border px-2.5 py-1">
          Phase 2
        </span>
      </div>

      <div class="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div class="sm:col-span-2">
          <label for="search" class="sr-only">Search</label>
          <input
            id="search"
            disabled
            placeholder="Search packages (coming soon)"
            class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm text-muted-foreground
                   disabled:opacity-60 disabled:cursor-not-allowed"
          />
        </div>
        <div>
          <label for="category" class="sr-only">Category</label>
          <select
            id="category"
            disabled
            class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm text-muted-foreground
                   disabled:opacity-60 disabled:cursor-not-allowed"
          >
            <option>All categories (coming soon)</option>
          </select>
        </div>
      </div>

      <div class="mt-6 rounded-xl border border-border bg-muted/20 p-4">
        <div class="text-sm font-medium">No packages yet</div>
        <p class="mt-1 text-sm text-muted-foreground">
          Implement Phase 2 to populate this page. In the meantime, you can confirm multi-tenancy and
          seeded data via AshAdmin.
        </p>
        <div class="mt-3 flex flex-wrap gap-2">
          <a
            href="/admin/tenant"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
          >
            Choose tenant
          </a>
          <a
            href="/admin"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
          >
            View resources
          </a>
        </div>
      </div>
    </div>

    <aside class="rounded-2xl border border-border bg-card text-card-foreground p-6">
      <h3 class="font-semibold">What’s coming</h3>
      <ul class="mt-3 space-y-3 text-sm text-muted-foreground">
        <li>
          <span class="text-foreground font-medium">Packages</span>:
          install agents/workflows/skills into an org.
        </li>
        <li>
          <span class="text-foreground font-medium">Installations</span>:
          background install job + status tracking.
        </li>
        <li>
          <span class="text-foreground font-medium">Reviews</span>:
          ratings, verified publishers, and trust signals.
        </li>
      </ul>

      <div class="mt-6">
        <a
          use:inertia
          href="/"
          class="inline-flex w-full items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-10 px-4"
        >
          Back to Home
        </a>
      </div>
    </aside>
  </section>
</AppShell>
