<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import { onMount } from "svelte";

    export let title: string = "FleetPrompt";
    export let subtitle: string | null = null;

    // Optional: show an admin entry point (AshAdmin is not Inertia, but it’s a useful affordance)
    export let showAdminLink: boolean = true;

    // Auth/tenant context (recommended to be provided via shared Inertia props, then passed into AppShell)
    export let user: {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    } | null = null;

    // Tenant context
    // `tenant` is intended to be a slug like "demo"; `tenant_schema` can be "org_demo"
    export let tenant: string | null = null;
    export let tenant_schema: string | null = null;

    // Multi-org context (optional; only shown when provided)
    type OrganizationOption = {
        id: string;
        name?: string | null;
        slug?: string | null;
        tier?: string | null;
    };

    export let organizations: OrganizationOption[] | null = null;

    export let current_organization: OrganizationOption | null = null;

    let isLoggingOut = false;
    let isSwitchingOrg = false;

    let selectedOrgId = "";

    $: {
        const preferred =
            current_organization?.id ?? organizations?.[0]?.id ?? "";
        if (!selectedOrgId && preferred) selectedOrgId = preferred;
    }

    let currentPath = "";

    const updateCurrentPath = () => {
        if (typeof window === "undefined") return;
        currentPath = window.location.pathname;
    };

    onMount(() => {
        updateCurrentPath();

        // Keep nav highlighting in sync with Inertia client-side navigation.
        // Inertia dispatches DOM events; we listen for them instead of importing a router.
        const handler = () => updateCurrentPath();

        document.addEventListener("inertia:navigate", handler);
        document.addEventListener("inertia:finish", handler);

        return () => {
            document.removeEventListener("inertia:navigate", handler);
            document.removeEventListener("inertia:finish", handler);
        };
    });

    const isActive = (href: string) => {
        if (!currentPath) return false;
        if (href === "/") return currentPath === "/";
        return currentPath === href || currentPath.startsWith(href + "/");
    };

    const linkClass = (href: string) => {
        const base =
            "inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors";
        const active = "bg-muted text-foreground";
        const inactive =
            "text-muted-foreground hover:text-foreground hover:bg-muted/60";

        return `${base} ${isActive(href) ? active : inactive}`;
    };

    const getCsrfToken = () =>
        document
            .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
            ?.getAttribute("content") ?? "";

    const tenantLabel = () => {
        const raw = (tenant ?? tenant_schema ?? "").trim();
        if (!raw) return null;
        return raw.startsWith("org_") ? raw.slice("org_".length) : raw;
    };

    const orgLabel = (org: OrganizationOption | null | undefined) => {
        if (!org) return "Organization";
        const name = (org.name ?? "").trim();
        if (name) return name;

        const slug = (org.slug ?? "").trim();
        if (slug) return slug;

        return org.id;
    };

    async function switchOrganization(organizationId: string) {
        const orgId = (organizationId ?? "").trim();
        if (!orgId) return;
        if (isSwitchingOrg) return;

        // Avoid redundant POSTs if we're already on that org.
        if (current_organization?.id && current_organization.id === orgId)
            return;

        isSwitchingOrg = true;

        try {
            const csrf = getCsrfToken();
            const redirectTo =
                typeof window !== "undefined"
                    ? window.location.pathname + window.location.search
                    : "/dashboard";

            const res = await fetch("/org/select", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({
                    organization_id: orgId,
                    redirect_to: redirectTo,
                }),
            });

            if (!res.ok) {
                // Fall back to a hard reload; the backend may have set cookies/session anyway.
                window.location.reload();
                return;
            }

            // Prefer the backend-provided redirect_to if returned.
            let next = redirectTo;
            try {
                const data = await res.json().catch(() => null);
                const candidate = (data as any)?.redirect_to;
                if (typeof candidate === "string" && candidate.trim() !== "") {
                    next = candidate;
                }
            } catch (_err) {
                // ignore
            }

            window.location.href = next;
        } finally {
            isSwitchingOrg = false;
        }
    }

    async function logout() {
        if (isLoggingOut) return;

        isLoggingOut = true;

        try {
            const csrf = getCsrfToken();

            await fetch("/logout", {
                method: "DELETE",
                headers: {
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
            });
        } catch (_err) {
            // If logout fails for any reason, still fall through to a hard navigation.
        } finally {
            window.location.href = "/";
        }
    }
</script>

<div class="min-h-screen bg-background text-foreground">
    <header
        class="sticky top-0 z-40 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60"
    >
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
            <div class="flex h-14 items-center justify-between gap-4">
                <div class="flex items-center gap-3 min-w-0">
                    <a
                        use:inertia
                        href="/"
                        class="flex h-14 items-center gap-2 font-semibold tracking-tight truncate"
                        aria-label="FleetPrompt Home"
                    >
                        <img
                            src="/images/logo-with-text.png"
                            alt="FleetPrompt"
                            class="h-full w-auto object-contain block"
                            loading="eager"
                        />
                    </a>

                    <nav class="hidden md:flex items-center gap-1">
                        <a
                            use:inertia
                            href="/dashboard"
                            class={linkClass("/dashboard")}
                        >
                            Dashboard
                        </a>
                        <a
                            use:inertia
                            href="/forums"
                            class={linkClass("/forums")}
                        >
                            Forums
                        </a>
                        <a
                            use:inertia
                            href="/marketplace"
                            class={linkClass("/marketplace")}
                        >
                            Marketplace
                        </a>
                        <a use:inertia href="/chat" class={linkClass("/chat")}>
                            Chat
                        </a>

                        {#if showAdminLink}
                            <!-- AshAdmin (LiveView) lives outside Inertia; use plain href -->
                            <a
                                href="/admin/tenant"
                                class="inline-flex items-center rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
                            >
                                Admin
                            </a>
                        {/if}
                    </nav>
                </div>

                <div class="flex items-center gap-3">
                    <slot name="nav-right">
                        {#if organizations && organizations.length > 1}
                            <div class="hidden sm:flex items-center gap-2">
                                <span class="text-xs text-muted-foreground">
                                    Org
                                </span>

                                <select
                                    class="h-9 rounded-md border border-border bg-background px-2.5 text-sm text-foreground
                                           hover:bg-muted/40 transition-colors disabled:opacity-60"
                                    bind:value={selectedOrgId}
                                    on:change={(e) =>
                                        switchOrganization(
                                            (
                                                e.currentTarget as HTMLSelectElement
                                            ).value,
                                        )}
                                    disabled={isSwitchingOrg}
                                    aria-label="Select organization"
                                    title="Switch organization"
                                >
                                    {#each organizations as org (org.id)}
                                        <option value={org.id}>
                                            {orgLabel(org)}
                                        </option>
                                    {/each}
                                </select>
                            </div>
                        {:else if current_organization}
                            <span
                                class="hidden sm:inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                                title="Current organization"
                            >
                                Org:
                                <span class="ml-1 font-medium text-foreground">
                                    {orgLabel(current_organization)}
                                </span>
                            </span>
                        {/if}

                        {#if tenantLabel()}
                            <a
                                href="/admin/tenant"
                                class="hidden sm:inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground hover:text-foreground hover:bg-muted/50 transition-colors"
                                title="Tenant context (schema-per-tenant)"
                            >
                                Tenant: <span
                                    class="ml-1 font-medium text-foreground"
                                    >{tenantLabel()}</span
                                >
                            </a>
                        {/if}

                        {#if user}
                            <div
                                class="hidden sm:flex flex-col items-end leading-tight"
                            >
                                <span class="text-sm font-medium">
                                    {user.name ?? user.email ?? "Signed in"}
                                </span>
                                {#if user.email && user.name}
                                    <span class="text-xs text-muted-foreground"
                                        >{user.email}</span
                                    >
                                {/if}
                            </div>

                            <button
                                type="button"
                                class="inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 disabled:opacity-60 disabled:pointer-events-none"
                                on:click={logout}
                                disabled={isLoggingOut}
                                title="Sign out"
                            >
                                {#if isLoggingOut}
                                    Signing out…
                                {:else}
                                    Sign out
                                {/if}
                            </button>
                        {:else}
                            <a
                                use:inertia
                                href="/login"
                                class="inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors
                       bg-primary text-primary-foreground hover:bg-primary/90 h-9"
                            >
                                Sign in
                            </a>
                        {/if}
                    </slot>
                </div>
            </div>
        </div>
    </header>

    <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div class="mb-6 flex items-start justify-between gap-4">
            <div class="min-w-0">
                <h1 class="text-2xl font-semibold tracking-tight truncate">
                    {title}
                </h1>
                {#if subtitle}
                    <p class="mt-1 text-sm text-muted-foreground">
                        {subtitle}
                    </p>
                {/if}
            </div>

            <div class="flex items-center gap-2">
                <slot name="header-actions" />
            </div>
        </div>

        <slot />
    </main>

    <footer class="border-t">
        <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
            <div
                class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 text-xs text-muted-foreground"
            >
                <div>
                    © {new Date().getFullYear()} FleetPrompt
                </div>
                <div class="flex items-center gap-4">
                    <a
                        class="hover:text-foreground transition-colors"
                        href="/privacy">Privacy</a
                    >
                    <a
                        class="hover:text-foreground transition-colors"
                        href="/terms">Terms</a
                    >
                </div>
            </div>
        </div>
    </footer>
</div>
