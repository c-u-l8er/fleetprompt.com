<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    export let title: string = "Settings";
    export let subtitle: string | null =
        "Account and application settings. (Coming soon.)";

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

    // Local-only placeholders (no persistence yet)
    let emailNotifications = true;
    let productUpdates = false;
    let darkModeHint =
        "Use the theme toggle in the header/footer (persistence handled elsewhere).";
</script>

<svelte:head>
    <title>{title || "Settings"} • FleetPrompt</title>
</svelte:head>

<AppShell
    title={title || "Settings"}
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
            href="/profile"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Profile
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
        <div class="flex flex-col gap-6">
            <div class="min-w-0">
                <h2 class="text-lg font-semibold tracking-tight">Settings</h2>
                <p class="mt-1 text-sm text-muted-foreground">
                    These controls are UI scaffolds for now. They don’t persist yet.
                </p>
            </div>

            <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <!-- Account -->
                <div class="rounded-2xl border border-border bg-muted/10 p-4">
                    <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                            <div class="text-sm font-medium">Account</div>
                            <div class="mt-1 text-xs text-muted-foreground">
                                Signed in as {user?.email ?? "—"}
                            </div>
                        </div>

                        <a
                            use:inertia
                            href="/profile"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                   border border-border bg-background hover:bg-muted h-9 px-3"
                        >
                            Manage
                        </a>
                    </div>

                    <div class="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <div class="rounded-xl border border-border bg-background/60 p-3">
                            <div class="text-xs font-medium text-muted-foreground">
                                Organization
                            </div>
                            <div class="mt-1 text-sm font-medium truncate">
                                {current_organization?.name ??
                                    current_organization?.slug ??
                                    current_organization?.id ??
                                    "—"}
                            </div>
                        </div>

                        <div class="rounded-xl border border-border bg-background/60 p-3">
                            <div class="text-xs font-medium text-muted-foreground">
                                Tenant
                            </div>
                            <div class="mt-1 text-sm font-medium truncate">
                                {tenant ?? "public"}
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Appearance -->
                <div class="rounded-2xl border border-border bg-muted/10 p-4">
                    <div class="text-sm font-medium">Appearance</div>
                    <div class="mt-1 text-xs text-muted-foreground">
                        {darkModeHint}
                    </div>

                    <div class="mt-4 rounded-xl border border-border bg-background/60 p-3">
                        <div class="flex items-center justify-between gap-3">
                            <div class="min-w-0">
                                <div class="text-sm font-medium">Theme</div>
                                <div class="text-xs text-muted-foreground">
                                    Toggle via the header control.
                                </div>
                            </div>

                            <span
                                class="inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                            >
                                Coming soon
                            </span>
                        </div>
                    </div>
                </div>

                <!-- Notifications -->
                <div class="rounded-2xl border border-border bg-muted/10 p-4">
                    <div class="text-sm font-medium">Notifications</div>
                    <div class="mt-1 text-xs text-muted-foreground">
                        Placeholder preferences (not saved yet).
                    </div>

                    <div class="mt-4 space-y-3">
                        <label
                            class="flex items-center justify-between gap-3 rounded-xl border border-border bg-background/60 p-3"
                        >
                            <div class="min-w-0">
                                <div class="text-sm font-medium">
                                    Email notifications
                                </div>
                                <div class="text-xs text-muted-foreground">
                                    Security and important account messages.
                                </div>
                            </div>
                            <input
                                type="checkbox"
                                class="h-4 w-4"
                                bind:checked={emailNotifications}
                            />
                        </label>

                        <label
                            class="flex items-center justify-between gap-3 rounded-xl border border-border bg-background/60 p-3"
                        >
                            <div class="min-w-0">
                                <div class="text-sm font-medium">
                                    Product updates
                                </div>
                                <div class="text-xs text-muted-foreground">
                                    Feature announcements and tips.
                                </div>
                            </div>
                            <input
                                type="checkbox"
                                class="h-4 w-4"
                                bind:checked={productUpdates}
                            />
                        </label>
                    </div>
                </div>

                <!-- Security -->
                <div class="rounded-2xl border border-border bg-muted/10 p-4">
                    <div class="text-sm font-medium">Security</div>
                    <div class="mt-1 text-xs text-muted-foreground">
                        Password resets, sessions, and API keys will live here.
                    </div>

                    <div class="mt-4 space-y-2">
                        <div class="rounded-xl border border-border bg-background/60 p-3">
                            <div class="flex items-center justify-between gap-3">
                                <div class="min-w-0">
                                    <div class="text-sm font-medium">
                                        Change password
                                    </div>
                                    <div class="text-xs text-muted-foreground">
                                        Coming soon.
                                    </div>
                                </div>
                                <span
                                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                                >
                                    Coming soon
                                </span>
                            </div>
                        </div>

                        <div class="rounded-xl border border-border bg-background/60 p-3">
                            <div class="flex items-center justify-between gap-3">
                                <div class="min-w-0">
                                    <div class="text-sm font-medium">
                                        Active sessions
                                    </div>
                                    <div class="text-xs text-muted-foreground">
                                        View and revoke sessions. Coming soon.
                                    </div>
                                </div>
                                <span
                                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                                >
                                    Coming soon
                                </span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="rounded-2xl border border-border bg-muted/20 p-4">
                <div class="text-sm font-medium">Notes</div>
                <p class="mt-1 text-sm text-muted-foreground">
                    The header now uses two dropdowns: one for org/tenant context and one for your user
                    account. This page exists so those links have real destinations while the underlying
                    features are implemented.
                </p>
            </div>
        </div>
    </section>
</AppShell>
