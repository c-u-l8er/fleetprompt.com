<script lang="ts">
  import { inertia } from "@inertiajs/svelte";
  import AppShell from "../lib/components/AppShell.svelte";

  /**
   * Placeholder page.
   *
   * This will become the main chat UX (Phase 3),
   * likely using SSE streaming on the backend + incremental rendering on the frontend.
   */
</script>

<svelte:head>
  <title>Chat • FleetPrompt</title>
</svelte:head>

<AppShell
  title="Chat"
  subtitle="Placeholder — streaming chat UI will land here. Use AshAdmin to inspect seeded data for now."
  showAdminLink={true}
>
  <section class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8">
    <div class="max-w-2xl">
      <h2 class="text-xl font-semibold tracking-tight">Chat is coming next</h2>

      <p class="mt-2 text-sm text-muted-foreground">
        This route exists so navigation and layout can be validated early. Next steps
        will add:
      </p>

      <ul class="mt-4 space-y-2 text-sm text-muted-foreground list-disc pl-5">
        <li>conversation list + history</li>
        <li>message composer with keyboard UX</li>
        <li>streaming responses (SSE) + partial rendering</li>
        <li>actions (install package, view package, create agent)</li>
      </ul>

      <div class="mt-6 flex flex-wrap items-center gap-3">
        <a
          use:inertia
          href="/dashboard"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-10 px-4"
        >
          Back to Dashboard
        </a>

        <a
          use:inertia
          href="/marketplace"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-10 px-4"
        >
          Browse Marketplace
        </a>

        <a
          href="/admin/tenant"
          class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4"
        >
          Open Admin (select tenant)
        </a>
      </div>

      <div class="mt-6 rounded-xl border border-border bg-background p-4">
        <p class="text-xs text-muted-foreground">
          Tip: For tenant-scoped resources (like Agents), visit <code>/admin/tenant</code> and select
          <code>demo</code> to browse <code>org_demo</code>.
        </p>
      </div>
    </div>
  </section>

  <section class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
    <div class="rounded-xl border border-border bg-card p-5">
      <div class="font-semibold">Status</div>
      <p class="mt-2 text-sm text-muted-foreground">
        UI scaffold only. No chat API calls yet.
      </p>
    </div>

    <div class="rounded-xl border border-border bg-card p-5">
      <div class="font-semibold">Planned transport</div>
      <p class="mt-2 text-sm text-muted-foreground">
        Server-Sent Events (SSE) for streaming; fall back to JSON for non-stream clients.
      </p>
    </div>

    <div class="rounded-xl border border-border bg-card p-5">
      <div class="font-semibold">Planned storage</div>
      <p class="mt-2 text-sm text-muted-foreground">
        Conversations + messages as Ash resources, scoped by organization tenant.
      </p>
    </div>
  </section>
</AppShell>
