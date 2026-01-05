<script lang="ts">
  import { inertia } from "@inertiajs/svelte";

  export let title: string;
  export let message: string;
</script>

<svelte:head>
  <title>{title || "Dashboard"} • FleetPrompt</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground">
  <!-- Top bar -->
  <header class="border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
    <div class="mx-auto max-w-6xl px-6 py-5 flex items-center justify-between gap-4">
      <div class="min-w-0">
        <div class="flex items-center gap-3">
          <div class="h-9 w-9 rounded-lg bg-primary/15 border border-border flex items-center justify-center">
            <span class="text-sm font-semibold text-primary">FP</span>
          </div>
          <div class="min-w-0">
            <h1 class="text-lg font-semibold leading-6 truncate">
              {title || "Dashboard"}
            </h1>
            <p class="text-xs text-muted-foreground truncate">
              {message || "Welcome back."}
            </p>
          </div>
        </div>
      </div>

      <nav class="flex items-center gap-2">
        <a
          use:inertia
          href="/"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-9 px-3"
        >
          Home
        </a>
        <a
          use:inertia
          href="/marketplace"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-9 px-3"
        >
          Marketplace
        </a>
        <a
          href="/admin"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
        >
          Admin
        </a>
      </nav>
    </div>
  </header>

  <main class="mx-auto max-w-6xl px-6 py-10">
    <!-- Quick actions -->
    <section>
      <h2 class="text-sm font-semibold tracking-wide text-muted-foreground uppercase">
        Quick actions
      </h2>

      <div class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <a
          href="/admin/tenant"
          class="group rounded-xl border border-border bg-card text-card-foreground p-5 hover:bg-muted/30 transition-colors"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="font-semibold">Select tenant for Admin</div>
              <p class="mt-1 text-sm text-muted-foreground">
                Choose an organization schema (e.g. <code>org_demo</code>) to browse tenant-scoped resources like Agents.
              </p>
            </div>
            <span class="text-muted-foreground group-hover:text-foreground transition-colors">→</span>
          </div>
        </a>

        <a
          href="/admin"
          class="group rounded-xl border border-border bg-card text-card-foreground p-5 hover:bg-muted/30 transition-colors"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="font-semibold">Open AshAdmin</div>
              <p class="mt-1 text-sm text-muted-foreground">
                Manage Organizations, Users, Skills, and Agents (tenant-scoped).
              </p>
            </div>
            <span class="text-muted-foreground group-hover:text-foreground transition-colors">→</span>
          </div>
        </a>

        <a
          use:inertia
          href="/marketplace"
          class="group rounded-xl border border-border bg-card text-card-foreground p-5 hover:bg-muted/30 transition-colors"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="font-semibold">Browse Marketplace</div>
              <p class="mt-1 text-sm text-muted-foreground">
                Discover packages, agents, and workflows you can install into your organization.
              </p>
            </div>
            <span class="text-muted-foreground group-hover:text-foreground transition-colors">→</span>
          </div>
        </a>
      </div>
    </section>

    <!-- Status + placeholders -->
    <section class="mt-10 grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 rounded-xl border border-border bg-card p-6">
        <h3 class="font-semibold">Getting started</h3>
        <p class="mt-2 text-sm text-muted-foreground">
          This dashboard is a UI scaffold. Next we’ll wire it to real data (organizations, agents, executions, and installs)
          and add navigation, empty states, and onboarding.
        </p>

        <ul class="mt-4 text-sm space-y-2 text-muted-foreground">
          <li>
            <span class="text-foreground font-medium">1)</span>
            Visit <a class="text-primary hover:underline" href="/admin/tenant">Admin tenant selector</a> and choose <code>demo</code>.
          </li>
          <li>
            <span class="text-foreground font-medium">2)</span>
            Browse tenant-scoped Agents in <a class="text-primary hover:underline" href="/admin">AshAdmin</a>.
          </li>
          <li>
            <span class="text-foreground font-medium">3)</span>
            Return here and we’ll add “Recent agents”, “Recent executions”, and “Usage”.
          </li>
        </ul>
      </div>

      <div class="rounded-xl border border-border bg-card p-6">
        <h3 class="font-semibold">Environment</h3>
        <div class="mt-3 space-y-3 text-sm">
          <div class="flex items-center justify-between gap-3">
            <span class="text-muted-foreground">Backend</span>
            <span class="font-medium">Phoenix + Ash</span>
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class="text-muted-foreground">Frontend</span>
            <span class="font-medium">Svelte + Inertia</span>
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class="text-muted-foreground">Admin</span>
            <span class="font-medium">AshAdmin (LiveView)</span>
          </div>
        </div>

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
      </div>
    </section>
  </main>
</div>
