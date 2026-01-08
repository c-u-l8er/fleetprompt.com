<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import { onMount } from "svelte";

    export let title: string = "FleetPrompt";
    export let subtitle: string | null = null;

    // Prefer a digested static URL from the server via:
    // - `logo_with_text_url` prop (e.g. shared Inertia prop), or
    // - root layout meta tag: <meta name="fp-logo-with-text" content="...">
    export let logo_with_text_url: string | null = null;

    const getLogoWithTextUrlFromMeta = () => {
        if (typeof document === "undefined") return "";

        return (
            document
                .querySelector<HTMLMetaElement>(
                    'meta[name="fp-logo-with-text"]',
                )
                ?.getAttribute("content") ?? ""
        );
    };

    const resolveLogoWithTextUrl = () => {
        const fromProp = (logo_with_text_url ?? "").trim();
        if (fromProp) return fromProp;

        const fromMeta = getLogoWithTextUrlFromMeta().trim();
        if (fromMeta) return fromMeta;

        return "/images/logo-with-text.png";
    };

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

    // Header dropdown menus
    let orgMenuOpen = false;
    let userMenuOpen = false;

    let orgButtonEl: HTMLElement | null = null;
    let orgMenuEl: HTMLElement | null = null;

    let userButtonEl: HTMLElement | null = null;
    let userMenuEl: HTMLElement | null = null;

    const closeOrgMenu = () => {
        orgMenuOpen = false;
    };

    const closeUserMenu = () => {
        userMenuOpen = false;
    };

    const closeAllMenus = () => {
        orgMenuOpen = false;
        userMenuOpen = false;
    };

    const toggleOrgMenu = () => {
        orgMenuOpen = !orgMenuOpen;
        if (orgMenuOpen) userMenuOpen = false;
    };

    const toggleUserMenu = () => {
        userMenuOpen = !userMenuOpen;
        if (userMenuOpen) orgMenuOpen = false;
    };

    $: currentOrgForLabel = current_organization ?? organizations?.[0] ?? null;

    const updateCurrentPath = () => {
        if (typeof window === "undefined") return;
        currentPath = window.location.pathname;
    };

    onMount(() => {
        updateCurrentPath();

        // Keep nav highlighting in sync with Inertia client-side navigation.
        // Inertia dispatches DOM events; we listen for them instead of importing a router.
        const handler = () => {
            closeAllMenus();
            updateCurrentPath();
        };

        const onDocumentClick = (e: MouseEvent) => {
            const target = e.target as Node | null;
            if (!target) return;

            if (orgMenuOpen) {
                const inOrg =
                    (orgButtonEl && orgButtonEl.contains(target)) ||
                    (orgMenuEl && orgMenuEl.contains(target));
                if (!inOrg) orgMenuOpen = false;
            }

            if (userMenuOpen) {
                const inUser =
                    (userButtonEl && userButtonEl.contains(target)) ||
                    (userMenuEl && userMenuEl.contains(target));
                if (!inUser) userMenuOpen = false;
            }
        };

        const onDocumentKeydown = (e: KeyboardEvent) => {
            if (e.key === "Escape") closeAllMenus();
        };

        document.addEventListener("inertia:navigate", handler);
        document.addEventListener("inertia:finish", handler);

        // Close dropdowns when clicking away / pressing Escape
        document.addEventListener("click", onDocumentClick, true);
        document.addEventListener("keydown", onDocumentKeydown);

        return () => {
            document.removeEventListener("inertia:navigate", handler);
            document.removeEventListener("inertia:finish", handler);

            document.removeEventListener("click", onDocumentClick, true);
            document.removeEventListener("keydown", onDocumentKeydown);
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
                            src={resolveLogoWithTextUrl()}
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
                    </nav>
                </div>

                <div class="flex items-center gap-3">
                    <slot name="nav-right">
                        {#if user}
                            <!-- Org/Tenant dropdown -->
                            <div class="relative">
                                <button
                                    type="button"
                                    class="inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors
                                           border border-border bg-background hover:bg-muted h-9 max-w-[18rem]"
                                    aria-haspopup="menu"
                                    aria-expanded={orgMenuOpen}
                                    on:click={toggleOrgMenu}
                                    bind:this={orgButtonEl}
                                    title="Organization / tenant"
                                >
                                    <span class="truncate">
                                        {orgLabel(currentOrgForLabel)}
                                    </span>
                                    {#if tenantLabel()}
                                        <span
                                            class="text-xs text-muted-foreground"
                                        >
                                            {tenantLabel()}
                                        </span>
                                    {/if}
                                    <svg
                                        class="h-4 w-4 text-muted-foreground"
                                        viewBox="0 0 20 20"
                                        fill="currentColor"
                                        aria-hidden="true"
                                    >
                                        <path
                                            fill-rule="evenodd"
                                            d="M5.23 7.21a.75.75 0 0 1 1.06.02L10 10.94l3.71-3.71a.75.75 0 1 1 1.06 1.06l-4.24 4.24a.75.75 0 0 1-1.06 0L5.21 8.29a.75.75 0 0 1 .02-1.08z"
                                            clip-rule="evenodd"
                                        />
                                    </svg>
                                </button>

                                {#if orgMenuOpen}
                                    <div
                                        class="absolute right-0 mt-2 w-80 rounded-md border border-border bg-background shadow-lg overflow-hidden z-50"
                                        role="menu"
                                        bind:this={orgMenuEl}
                                    >
                                        <div
                                            class="px-3 py-2 text-xs font-medium text-muted-foreground bg-muted/20"
                                        >
                                            Organization / tenant
                                        </div>

                                        {#if organizations && organizations.length > 0}
                                            <div class="py-1">
                                                {#each organizations as org (org.id)}
                                                    <button
                                                        type="button"
                                                        class="flex w-full items-center justify-between gap-3 px-3 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors
                                                               disabled:opacity-60 disabled:pointer-events-none"
                                                        on:click={() => {
                                                            closeOrgMenu();
                                                            switchOrganization(
                                                                org.id,
                                                            );
                                                        }}
                                                        disabled={isSwitchingOrg}
                                                        role="menuitem"
                                                        title="Switch organization"
                                                    >
                                                        <span class="truncate">
                                                            {orgLabel(org)}
                                                        </span>
                                                        {#if current_organization?.id === org.id}
                                                            <span
                                                                class="text-xs text-muted-foreground"
                                                            >
                                                                Current
                                                            </span>
                                                        {/if}
                                                    </button>
                                                {/each}
                                            </div>
                                        {/if}

                                        <div class="h-px bg-border"></div>

                                        <div class="px-3 py-2">
                                            <div
                                                class="text-xs font-medium text-muted-foreground"
                                            >
                                                Tenant
                                            </div>
                                            <div class="mt-1 text-sm">
                                                {#if tenantLabel()}
                                                    <span class="font-medium"
                                                        >{tenantLabel()}</span
                                                    >
                                                {:else}
                                                    <span
                                                        class="text-muted-foreground"
                                                        >public</span
                                                    >
                                                {/if}
                                            </div>

                                            <div
                                                class="mt-3 flex flex-col gap-1"
                                            >
                                                <a
                                                    href="/admin/tenant"
                                                    class="inline-flex items-center rounded-md px-2.5 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors"
                                                    role="menuitem"
                                                    on:click={() =>
                                                        closeOrgMenu()}
                                                >
                                                    Select tenant
                                                </a>
                                                <a
                                                    href="/admin/portal"
                                                    class="inline-flex items-center rounded-md px-2.5 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors"
                                                    role="menuitem"
                                                    on:click={() =>
                                                        closeOrgMenu()}
                                                >
                                                    Admin portal
                                                </a>
                                                <a
                                                    href="/admin"
                                                    class="inline-flex items-center rounded-md px-2.5 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors"
                                                    role="menuitem"
                                                    on:click={() =>
                                                        closeOrgMenu()}
                                                >
                                                    Open admin
                                                </a>
                                            </div>
                                        </div>
                                    </div>
                                {/if}
                            </div>

                            <!-- User dropdown -->
                            <div class="relative">
                                <button
                                    type="button"
                                    class="inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors
                                           border border-border bg-background hover:bg-muted h-9 max-w-[16rem]"
                                    aria-haspopup="menu"
                                    aria-expanded={userMenuOpen}
                                    on:click={toggleUserMenu}
                                    bind:this={userButtonEl}
                                    title="User menu"
                                >
                                    <span class="truncate">
                                        {user.name ?? user.email ?? "Account"}
                                    </span>
                                    <svg
                                        class="h-4 w-4 text-muted-foreground"
                                        viewBox="0 0 20 20"
                                        fill="currentColor"
                                        aria-hidden="true"
                                    >
                                        <path
                                            fill-rule="evenodd"
                                            d="M5.23 7.21a.75.75 0 0 1 1.06.02L10 10.94l3.71-3.71a.75.75 0 1 1 1.06 1.06l-4.24 4.24a.75.75 0 0 1-1.06 0L5.21 8.29a.75.75 0 0 1 .02-1.08z"
                                            clip-rule="evenodd"
                                        />
                                    </svg>
                                </button>

                                {#if userMenuOpen}
                                    <div
                                        class="absolute right-0 mt-2 w-64 rounded-md border border-border bg-background shadow-lg overflow-hidden z-50"
                                        role="menu"
                                        bind:this={userMenuEl}
                                    >
                                        <div
                                            class="px-3 py-2 bg-muted/20 border-b border-border"
                                        >
                                            <div class="text-sm font-medium">
                                                {user.name ??
                                                    user.email ??
                                                    "Signed in"}
                                            </div>
                                            {#if user.email && user.name}
                                                <div
                                                    class="text-xs text-muted-foreground mt-0.5"
                                                >
                                                    {user.email}
                                                </div>
                                            {/if}
                                        </div>

                                        <div class="py-1">
                                            <a
                                                use:inertia
                                                href="/profile"
                                                class="flex items-center justify-between gap-3 px-3 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors"
                                                role="menuitem"
                                                on:click={() => {
                                                    closeUserMenu();
                                                }}
                                                title="Profile"
                                            >
                                                <span>Profile</span>
                                            </a>

                                            <a
                                                use:inertia
                                                href="/settings"
                                                class="flex items-center justify-between gap-3 px-3 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors"
                                                role="menuitem"
                                                on:click={() => {
                                                    closeUserMenu();
                                                }}
                                                title="Settings"
                                            >
                                                <span>Settings</span>
                                            </a>
                                        </div>

                                        <div class="h-px bg-border"></div>

                                        <div class="py-1">
                                            <button
                                                type="button"
                                                class="flex w-full items-center justify-between gap-3 px-3 py-2 text-sm text-foreground hover:bg-muted/60 transition-colors
                                                       disabled:opacity-60 disabled:pointer-events-none"
                                                on:click={() => {
                                                    closeUserMenu();
                                                    logout();
                                                }}
                                                disabled={isLoggingOut}
                                                role="menuitem"
                                                title="Sign out"
                                            >
                                                <span>
                                                    {#if isLoggingOut}
                                                        Signing out…
                                                    {:else}
                                                        Sign out
                                                    {/if}
                                                </span>
                                            </button>
                                        </div>
                                    </div>
                                {/if}
                            </div>
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
