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
    title="FleetPrompt"
    subtitle="Integration-first AI automation with a package marketplace, durable eventing, and multi-tenant isolation."
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

        <div class="relative p-6 sm:p-10">
            <div class="max-w-3xl">
                <div
                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                >
                    Integration-first • Package marketplace • Durable signals •
                    Website chat
                </div>

                <h2 class="mt-4 text-4xl sm:text-5xl font-bold tracking-tight">
                    Build automation that actually ships.
                </h2>

                <p class="mt-4 text-lg text-muted-foreground">
                    FleetPrompt is an AI automation platform designed for teams
                    who already live in chat and email. Install packages,
                    connect your tools, and run repeatable workflows with audit
                    trails, retries, and real observability.
                </p>

                <div class="mt-8 flex flex-wrap items-center gap-3">
                    {#if user}
                        <a
                            use:inertia
                            href="/dashboard"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                            bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4"
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

                    <a
                        use:inertia
                        href="/marketplace"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                        border border-border bg-background hover:bg-muted h-10 px-4"
                    >
                        Browse packages
                    </a>
                </div>

                <p class="mt-4 text-xs text-muted-foreground">
                    {message}
                </p>
            </div>
        </div>
    </section>

    <!-- WHY FLEETPROMPT -->
    <section class="mt-10">
        <div class="max-w-3xl">
            <h3 class="text-2xl font-semibold tracking-tight">
                Why teams choose FleetPrompt
            </h3>
            <p class="mt-2 text-sm text-muted-foreground">
                Most “AI agents” die at the same point: integrations,
                reliability, and governance. FleetPrompt is built around the
                hard parts: multi-tenancy, installation lifecycle, eventing, and
                execution.
            </p>
        </div>

        <div class="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div class="rounded-xl border border-border bg-card p-5">
                <div class="font-semibold">Package marketplace</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Install curated, opinionated packages that deliver a clear
                    job-to-be-done. Packages are how FleetPrompt scales value
                    across customers.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-5">
                <div class="font-semibold">Multi-tenant isolation</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Each organization runs in an isolated tenant context with
                    safer operations and clearer boundaries for data,
                    credentials, and execution.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-5">
                <div class="font-semibold">
                    Signals + directives (auditable)
                </div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Durable signals describe what happened. Directives describe
                    what you intended to change. Together they enable replay,
                    retries, and trustworthy automation.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-5">
                <div class="font-semibold">
                    Execution logs + cost visibility
                </div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Track runs, failures, retries, latency, and provider costs
                    so automation can be debugged and governed like real
                    production software.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-5">
                <div class="font-semibold">Integration-first by design</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    FleetPrompt is built to operate inside the tools you already
                    use instead of asking your team to migrate workflows into a
                    new system.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-5">
                <div class="font-semibold">Operator-grade reliability</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Background jobs, retries, and idempotency patterns are
                    first-class so you can safely automate high-volume,
                    real-world workflows.
                </p>
            </div>
        </div>
    </section>

    <!-- HOW IT WORKS -->
    <section
        class="mt-10 rounded-2xl border border-border bg-muted/20 p-6 sm:p-8"
    >
        <div class="max-w-3xl">
            <h3 class="text-2xl font-semibold tracking-tight">How it works</h3>
            <p class="mt-2 text-sm text-muted-foreground">
                A simple loop: install → connect → run → observe → iterate.
            </p>
        </div>

        <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="rounded-xl border border-border bg-background p-5">
                <div class="text-xs text-muted-foreground">Step 1</div>
                <div class="mt-1 font-semibold">Install a package</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Start from the marketplace and install a package into your
                    organization. Installs are tracked and auditable.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-background p-5">
                <div class="text-xs text-muted-foreground">Step 2</div>
                <div class="mt-1 font-semibold">Connect your tools</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Bind credentials securely and configure where results should
                    land (channels, inboxes, workflows).
                </p>
            </div>

            <div class="rounded-xl border border-border bg-background p-5">
                <div class="text-xs text-muted-foreground">Step 3</div>
                <div class="mt-1 font-semibold">Run + observe</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Trigger executions on-demand or on schedule. See logs,
                    signals, and outcomes—then refine safely.
                </p>
            </div>
        </div>

        <div class="mt-6 flex flex-wrap items-center gap-3">
            <a
                use:inertia
                href="/marketplace"
                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4"
            >
                Explore packages
            </a>

            {#if user}
                <a
                    use:inertia
                    href="/dashboard"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                    border border-border bg-background hover:bg-muted h-10 px-4"
                >
                    View your org
                </a>
            {:else}
                <a
                    use:inertia
                    href="/register"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                    border border-border bg-background hover:bg-muted h-10 px-4"
                >
                    Get started
                </a>
            {/if}
        </div>
    </section>

    <!-- INTEGRATIONS (PLANNED / ROADMAP) -->
    <section class="mt-10">
        <div class="max-w-3xl">
            <h3 class="text-2xl font-semibold tracking-tight">
                The communication triangle: email, IM, and website chat
            </h3>
            <p class="mt-2 text-sm text-muted-foreground">
                FleetPrompt’s strategy is integration-first. The core surfaces
                we’re targeting are the ones that cover the full customer
                communication loop: mailbox, instant messenger, and website
                chat. (Implementation and availability may vary by package.)
            </p>
        </div>

        <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="rounded-xl border border-border bg-card p-6">
                <div class="flex items-center justify-between gap-4">
                    <div class="font-semibold">Mattermost</div>
                    <span
                        class="rounded-full border border-border bg-muted/30 px-2.5 py-1 text-xs text-muted-foreground"
                    >
                        Instant messenger
                    </span>
                </div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Post digests, alerts, and workflow outcomes into channels
                    where your team already works. Designed around secure
                    tokens/webhooks and tenant-scoped credentials.
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-6">
                <div class="flex items-center justify-between gap-4">
                    <div class="font-semibold">Proton Mail</div>
                    <span
                        class="rounded-full border border-border bg-muted/30 px-2.5 py-1 text-xs text-muted-foreground"
                    >
                        Mailbox
                    </span>
                </div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Enable email-based workflows with privacy-first inboxes.
                    Proton Mail connectivity typically requires Proton Mail
                    Bridge for IMAP/SMTP (edge connector model).
                </p>
            </div>

            <div class="rounded-xl border border-border bg-card p-6">
                <div class="flex items-center justify-between gap-4">
                    <div class="font-semibold">Website Chat (Charla)</div>
                    <span
                        class="rounded-full border border-border bg-muted/30 px-2.5 py-1 text-xs text-muted-foreground"
                    >
                        Chatbot
                    </span>
                </div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Add an AI chat widget to your website and route
                    conversations into FleetPrompt’s signal-driven workflows—so
                    you can triage, follow up in email, and keep the team looped
                    in via IM.
                </p>
            </div>
        </div>
    </section>

    <!-- TRUST -->
    <section class="mt-10 rounded-2xl border border-border bg-card p-6 sm:p-8">
        <div class="max-w-3xl">
            <h3 class="text-2xl font-semibold tracking-tight">
                Trust is the feature
            </h3>
            <p class="mt-2 text-sm text-muted-foreground">
                Automation without governance becomes risk. FleetPrompt is
                designed so you can prove what happened, why it happened, and
                how to fix it.
            </p>
        </div>

        <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="rounded-xl border border-border bg-background p-5">
                <div class="font-semibold">Tenant boundaries</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Strong organizational isolation and explicit tenant context
                    propagation across UI, jobs, and future APIs.
                </p>
            </div>
            <div class="rounded-xl border border-border bg-background p-5">
                <div class="font-semibold">Secret-safe operations</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Credentials stay encrypted at rest and never appear in logs
                    or durable signals. Signals reference ids, not secrets.
                </p>
            </div>
            <div class="rounded-xl border border-border bg-background p-5">
                <div class="font-semibold">Replay + audit</div>
                <p class="mt-2 text-sm text-muted-foreground">
                    Signals can be replayed for debugging, and directives create
                    an auditable trail for installs and operational changes.
                </p>
            </div>
        </div>

        <div class="mt-8 flex flex-wrap items-center gap-3">
            <a
                use:inertia
                href="/marketplace"
                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4"
            >
                See the marketplace
            </a>

            <a
                use:inertia
                href="/chat"
                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                border border-border bg-background hover:bg-muted h-10 px-4"
            >
                Try the chat interface
            </a>
        </div>
    </section>
</AppShell>
