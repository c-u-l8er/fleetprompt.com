<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    export let title: string = "Dashboard";
    export let message: string = "Welcome to your FleetPrompt dashboard.";

    export let tenant: string | null = null;

    export let stats: {
        organizations: number;
        users: number;
        skills: number;
        agents: number;
    } | null = null;

    const safeStats = () => ({
        organizations: stats?.organizations ?? 0,
        users: stats?.users ?? 0,
        skills: stats?.skills ?? 0,
        agents: stats?.agents ?? 0,
    });
</script>

<svelte:head>
    <title>{title || "Dashboard"} • FleetPrompt</title>
</svelte:head>

<AppShell
    title={title || "Dashboard"}
    subtitle={message || "Welcome back."}
    showAdminLink={true}
>
    <svelte:fragment slot="header-actions">
        <a
            use:inertia
            href="/marketplace"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Marketplace
        </a>

        <a
            use:inertia
            href="/chat"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Chat
        </a>

        <a
            href="/admin/tenant"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
            title="AshAdmin runs on LiveView; select a tenant to browse tenant-scoped resources."
        >
            Admin
        </a>
    </svelte:fragment>

    <section
        class={`rounded-2xl border px-4 py-4 sm:px-6 sm:py-5 ${
            tenant
                ? "border-primary/30 bg-primary/10"
                : "border-border bg-muted/20"
        }`}
    >
        <div
            class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
        >
            <div class="min-w-0">
                <div class="font-medium">
                    Tenant context:
                    {#if tenant}
                        <code class="rounded bg-background/70 px-1.5 py-0.5"
                            >{tenant}</code
                        >
                    {:else}
                        <span class="text-muted-foreground">none selected</span>
                    {/if}
                </div>
                <div class="mt-1 text-xs text-muted-foreground">
                    {#if tenant}
                        Tenant-scoped data (like Agents) is counted within this
                        schema.
                    {:else}
                        Select a tenant (e.g. <code>demo</code>) to enable
                        tenant-scoped reads like Agents.
                    {/if}
                </div>
            </div>

            <div class="flex flex-wrap items-center gap-2">
                <a
                    href="/admin/tenant"
                    class="inline-flex items-center justify-center rounded-md text-xs font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-8 px-3"
                >
                    Select tenant
                </a>
                <a
                    href="/admin"
                    class="inline-flex items-center justify-center rounded-md text-xs font-medium transition-colors
                 bg-primary text-primary-foreground hover:bg-primary/90 h-8 px-3"
                >
                    Open AshAdmin
                </a>
            </div>
        </div>
    </section>

    <section class="mt-6 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div
            class="rounded-xl border border-border bg-card text-card-foreground p-5"
        >
            <div class="text-xs text-muted-foreground">Organizations</div>
            <div class="mt-2 text-2xl font-semibold tabular-nums">
                {safeStats().organizations}
            </div>
        </div>

        <div
            class="rounded-xl border border-border bg-card text-card-foreground p-5"
        >
            <div class="text-xs text-muted-foreground">Users</div>
            <div class="mt-2 text-2xl font-semibold tabular-nums">
                {safeStats().users}
            </div>
        </div>

        <div
            class="rounded-xl border border-border bg-card text-card-foreground p-5"
        >
            <div class="text-xs text-muted-foreground">Skills</div>
            <div class="mt-2 text-2xl font-semibold tabular-nums">
                {safeStats().skills}
            </div>
        </div>

        <div
            class="rounded-xl border border-border bg-card text-card-foreground p-5"
        >
            <div class="text-xs text-muted-foreground">Agents</div>
            <div class="mt-2 text-2xl font-semibold tabular-nums">
                {safeStats().agents}
            </div>
            {#if !tenant}
                <div class="mt-1 text-xs text-muted-foreground">
                    (select tenant)
                </div>
            {/if}
        </div>
    </section>

    <section class="mt-8">
        <h2
            class="text-sm font-semibold tracking-wide text-muted-foreground uppercase"
        >
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
                            Choose an organization schema (e.g. <code
                                >org_demo</code
                            >) to browse tenant-scoped resources like Agents.
                        </p>
                    </div>
                    <span
                        class="text-muted-foreground group-hover:text-foreground transition-colors"
                        >→</span
                    >
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
                            Manage Organizations, Users, Skills, and Agents
                            (tenant-scoped).
                        </p>
                    </div>
                    <span
                        class="text-muted-foreground group-hover:text-foreground transition-colors"
                        >→</span
                    >
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
                            Discover packages, agents, and workflows you can
                            install into your organization.
                        </p>
                    </div>
                    <span
                        class="text-muted-foreground group-hover:text-foreground transition-colors"
                        >→</span
                    >
                </div>
            </a>
        </div>
    </section>

    <section class="mt-10 grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 rounded-xl border border-border bg-card p-6">
            <h3 class="font-semibold">Getting started</h3>
            <p class="mt-2 text-sm text-muted-foreground">
                This dashboard now shows real counts from the backend. Next
                we’ll add “Recent agents”, “Recent executions”, and onboarding.
            </p>

            <ul class="mt-4 text-sm space-y-2 text-muted-foreground">
                <li>
                    <span class="text-foreground font-medium">1)</span>
                    Visit
                    <a class="text-primary hover:underline" href="/admin/tenant"
                        >Admin tenant selector</a
                    >
                    and choose <code>demo</code>.
                </li>
                <li>
                    <span class="text-foreground font-medium">2)</span>
                    Browse tenant-scoped Agents in
                    <a class="text-primary hover:underline" href="/admin"
                        >AshAdmin</a
                    >.
                </li>
                <li>
                    <span class="text-foreground font-medium">3)</span>
                    Return here to see the Agents count update for your selected tenant.
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
</AppShell>
