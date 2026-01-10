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
    <title>FleetPrompt: Agentic Intelligence Software</title>
</svelte:head>

<AppShell
    title="FleetPrompt"
    subtitle="Agentic Intelligence Software"
    showAdminLink={false}
    {user}
    {tenant}
    {tenant_schema}
    {organizations}
    {current_organization}
>
    <!-- HERO -->
    <section
        class="relative overflow-hidden rounded-2xl border border-border bg-card text-card-foreground"
    >
        <div
            class="absolute inset-0 bg-gradient-to-br from-primary/10 via-transparent to-transparent"
        ></div>

        <img
            src="/images/logo.png"
            alt="FleetPrompt Logo"
            class="absolute right-0 top-1/2 -translate-y-1/2 h-64 w-auto opacity-20 pointer-events-none hidden lg:block"
        />

        <div class="relative p-6 sm:p-10">
            <div class="max-w-3xl">
                <div
                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                >
                    Version: v0.0.1 (Ready for beta testing!)
                </div>

                <h2 class="mt-4 text-4xl sm:text-5xl font-bold tracking-tight">
                    Build automation that actually ships.
                </h2>

                <p class="mt-4 text-lg text-muted-foreground">
                    FleetPrompt is an AI automation platform designed for teams
                    that intelligently collaborate. Install packages, connect
                    your tools, and run repeatable workflows with audit trails,
                    retries, and real observability.
                </p>

                <div class="mt-8 flex flex-wrap items-center gap-3">
                    <a
                        href="https://fleetprompt.com"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                        bg-secondary text-secondary-foreground hover:bg-secondary/90 h-10 px-4"
                    >
                        Marketing Website
                    </a>
                    {#if user}
                        <a
                            use:inertia
                            href="/dashboard"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                            border border-border bg-background hover:bg-muted h-10 px-4"
                        >
                            Go to Dashboard
                        </a>
                    {:else}
                        <a
                            use:inertia
                            href="/register"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                            bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4"
                        >
                            Create an account
                        </a>

                        <a
                            use:inertia
                            href="/login"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                            border border-border bg-background hover:bg-muted h-10 px-4"
                        >
                            Sign in
                        </a>
                    {/if}
                </div>

                <p class="mt-4 text-xs text-muted-foreground">
                    {message}
                </p>
            </div>
        </div>
    </section>
</AppShell>
