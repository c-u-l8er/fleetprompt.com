<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    export let message: string;

    // Shared props (provided globally via Inertia shared props)
    export let user: {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    } | null = null;

    // Tenant context (slug + full schema name)
    export let tenant: string | null = null;
    export let tenant_schema: string | null = null;

    // Org selection context (for multi-org membership)
    export let organizations: Array<{
        id: string;
        name?: string | null;
        slug?: string | null;
        tier?: string | null;
    }> = [];

    export let current_organization: {
        id: string;
        name?: string | null;
        slug?: string | null;
        tier?: string | null;
    } | null = null;
</script>

<svelte:head>
    <title>FleetPrompt</title>
</svelte:head>

<AppShell
    title="FleetPrompt v0.0.1"
    subtitle="Deploy AI agent fleets in minutes — multi-tenant, package-driven, and chat-oriented. (Pre v1: use at your own risk!)"
    showAdminLink={true}
    {user}
    {tenant}
    {tenant_schema}
    {organizations}
    {current_organization}
>
    <section
        class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8"
    >
        <div class="max-w-2xl">
            <h2 class="text-3xl sm:text-4xl font-bold tracking-tight">
                Build, install, and run AI agents with confidence
            </h2>

            <p class="mt-3 text-muted-foreground">
                {message}
            </p>

            <div class="mt-6 flex flex-wrap items-center gap-3">
                <a
                    use:inertia
                    href="/dashboard"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                    bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4"
                >
                    Open Dashboard
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
                    border border-border bg-background hover:bg-muted h-10 px-4"
                >
                    Admin Tenant Selector
                </a>
            </div>

            <p class="mt-4 text-xs text-muted-foreground">
                Admin runs on LiveView (AshAdmin); the rest of the app uses
                Inertia + Svelte.
            </p>
        </div>
    </section>

    <section class="mt-8 grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="rounded-xl border border-border bg-card p-5">
            <div class="font-semibold">Multi-tenant by default</div>
            <p class="mt-2 text-sm text-muted-foreground">
                Each organization gets its own schema (<code>org_*</code>) for
                clean isolation and safer operations.
            </p>
        </div>

        <div class="rounded-xl border border-border bg-card p-5">
            <div class="font-semibold">Packages as building blocks</div>
            <p class="mt-2 text-sm text-muted-foreground">
                Install curated capabilities (agents, workflows, skills) from
                the marketplace into your org.
            </p>
        </div>

        <div class="rounded-xl border border-border bg-card p-5">
            <div class="font-semibold">Streaming chat + execution</div>
            <p class="mt-2 text-sm text-muted-foreground">
                Chat UX, execution logs, and workflow runs will share one
                consistent UI surface.
            </p>
        </div>
    </section>
</AppShell>
