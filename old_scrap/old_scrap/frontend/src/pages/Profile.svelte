<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    export let title: string = "Profile";
    export let subtitle: string | null = "Manage your account profile. (Coming soon.)";

    // Shared Inertia props (provided globally by the backend)
    export let user: {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    } | null = null;

    export let tenant: string | null = null;
    export let tenant_schema: string | null = null;

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
    <title>{title || "Profile"} • FleetPrompt</title>
</svelte:head>

<AppShell
    title={title || "Profile"}
    subtitle={subtitle}
    showAdminLink={true}
    {user}
    {tenant}
    {tenant_schema}
    {organizations}
    {current_organization}
>
    <svelte:fragment slot="header-actions">
        <a
            use:inertia
            href="/settings"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Settings
        </a>

        <a
            use:inertia
            href="/dashboard"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Dashboard
        </a>
    </svelte:fragment>

    <section class="rounded-2xl border border-border bg-background px-4 py-4 sm:px-6 sm:py-5">
        <div class="flex flex-col gap-4">
            <div class="min-w-0">
                <h2 class="text-lg font-semibold tracking-tight">Account</h2>
                <p class="mt-1 text-sm text-muted-foreground">
                    This page is a scaffold. Profile editing will be added next.
                </p>
            </div>

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div class="rounded-xl border border-border bg-muted/10 p-4">
                    <div class="text-xs font-medium text-muted-foreground">Name</div>
                    <div class="mt-1 text-sm font-medium">
                        {user?.name ?? "—"}
                    </div>
                </div>

                <div class="rounded-xl border border-border bg-muted/10 p-4">
                    <div class="text-xs font-medium text-muted-foreground">Email</div>
                    <div class="mt-1 text-sm font-medium">
                        {user?.email ?? "—"}
                    </div>
                </div>

                <div class="rounded-xl border border-border bg-muted/10 p-4">
                    <div class="text-xs font-medium text-muted-foreground">Role</div>
                    <div class="mt-1 text-sm font-medium">
                        {user?.role ?? "—"}
                    </div>
                </div>

                <div class="rounded-xl border border-border bg-muted/10 p-4">
                    <div class="text-xs font-medium text-muted-foreground">
                        Organization / Tenant
                    </div>
                    <div class="mt-1 text-sm font-medium truncate">
                        {current_organization?.name ??
                            current_organization?.slug ??
                            current_organization?.id ??
                            "—"}
                        <span class="text-muted-foreground">
                            {#if tenant}
                                · {tenant}
                            {:else}
                                · public
                            {/if}
                        </span>
                    </div>
                </div>
            </div>

            <div class="rounded-xl border border-border bg-muted/20 p-4">
                <div class="text-sm font-medium">Next steps</div>
                <ul class="mt-2 list-disc pl-5 text-sm text-muted-foreground space-y-1">
                    <li>Edit display name</li>
                    <li>Change password</li>
                    <li>API keys / sessions</li>
                    <li>Notification preferences</li>
                </ul>
            </div>
        </div>
    </section>
</AppShell>
