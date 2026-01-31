<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import { onMount } from "svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    type PricingModel = "free" | "freemium" | "paid" | "revenue_share";
    type Tier = "free" | "pro" | "enterprise";

    type MarketplacePackage = {
        id: string;
        name: string;
        slug: string;
        version?: string | null;
        description?: string | null;
        category?: string | null;
        icon_url?: string | null;
        pricing_model?: PricingModel | string | null;
        pricing_config?: Record<string, unknown> | null;
        install_count?: number | null;
        rating_avg?: string | number | null;
        rating_count?: number | null;
        is_verified?: boolean | null;
        is_featured?: boolean | null;
    };

    type Filters = {
        query?: string | null;
        category?: string | null;
        pricing?: string | null;
        tier?: string | null;
    };

    export let title: string = "Marketplace";
    export let subtitle: string =
        "Browse installable packages (agents, workflows, skills).";

    // Provided by the backend Marketplace controller (Phase 2 wiring).
    export let packages: MarketplacePackage[] = [];
    export let featured: MarketplacePackage[] = [];
    export let filters: Filters = {};

    type InstallationStatusEntry = {
        id?: string;
        status?:
            | "requested"
            | "installing"
            | "installed"
            | "failed"
            | "disabled"
            | string;
        enabled?: boolean;
        installed_at?: string | null;
        updated_at?: string | null;
        last_error?: string | null;
        last_error_at?: string | null;
    };

    // Provided by backend Marketplace controller (tenant-scoped installation states keyed by package slug).
    export let installation_status: Record<string, InstallationStatusEntry> =
        {};

    // Shared props (provided globally by the backend via Inertia shared props)
    export let user: {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    } | null = null;

    // `tenant` is intended to be a slug like "demo"; `tenant_schema` can be "org_demo"
    export let tenant: string | null = null;
    export let tenant_schema: string | null = null;

    // Organization selection context (multi-org membership)
    export let organizations: Array<{
        id: string;
        name: string;
        slug: string;
    }> | null = null;

    export let current_organization: {
        id: string;
        name: string;
        slug: string;
    } | null = null;

    const categories = [
        { value: "", label: "All categories" },
        { value: "operations", label: "Operations" },
        { value: "customer_service", label: "Customer service" },
        { value: "sales", label: "Sales" },
        { value: "data", label: "Data" },
        { value: "development", label: "Development" },
        { value: "marketing", label: "Marketing" },
        { value: "finance", label: "Finance" },
        { value: "hr", label: "HR" },
    ];

    const pricingModels = [
        { value: "", label: "All pricing" },
        { value: "free", label: "Free" },
        { value: "freemium", label: "Freemium" },
        { value: "paid", label: "Paid" },
        { value: "revenue_share", label: "Revenue share" },
    ];

    const tiers = [
        { value: "", label: "Any tier" },
        { value: "free", label: "Free" },
        { value: "pro", label: "Pro" },
        { value: "enterprise", label: "Enterprise" },
    ];

    const formatInstalls = (n: number | null | undefined) => {
        const value = typeof n === "number" ? n : 0;
        return value.toLocaleString();
    };

    const formatRating = (avg: string | number | null | undefined) => {
        if (avg === null || avg === undefined) return null;
        if (typeof avg === "number") return avg.toFixed(1);
        const parsed = Number(avg);
        return Number.isFinite(parsed) ? parsed.toFixed(1) : String(avg);
    };

    const formatPricing = (pkg: MarketplacePackage) => {
        const model = (pkg.pricing_model ?? "free") as PricingModel | string;
        const cfg = pkg.pricing_config ?? {};

        if (model === "free") return "Free";
        if (model === "freemium") return "Freemium";
        if (model === "paid") {
            const price = (cfg as any)?.price;
            if (typeof price === "number") return `$${price}/mo`;
            if (typeof price === "string" && price.trim() !== "")
                return `$${price}/mo`;
            return "Paid";
        }
        if (model === "revenue_share") {
            const pct = (cfg as any)?.percentage;
            if (typeof pct === "number") return `${pct}% rev share`;
            if (typeof pct === "string" && pct.trim() !== "")
                return `${pct}% rev share`;
            return "Revenue share";
        }
        return "Pricing";
    };

    type InstallResponse =
        | {
              ok: true;
              installation_id: string;
              status: string;
              enqueued: boolean;
              tenant: string;
              package: { slug: string; version: string };
          }
        | { ok: false; error: string; [key: string]: unknown };

    let installingBySlug: Record<string, boolean> = {};
    let queuedBySlug: Record<string, boolean> = {};
    let installedBySlug: Record<string, boolean> = {};
    let installErrorsBySlug: Record<string, string> = {};

    // Local copy that we can refresh by polling without relying on a full Inertia page reload.
    let installationStatusLocal: Record<string, InstallationStatusEntry> =
        installation_status ?? {};

    // Keep local map in sync if the server-provided prop changes (e.g., page reload or filter navigation).
    $: if (installation_status && typeof installation_status === "object") {
        installationStatusLocal = installation_status;
    }

    const getCsrfToken = () =>
        document
            .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
            ?.getAttribute("content") ?? "";

    const getKnownStatus = (slug: string) => {
        const s = (slug ?? "").trim();
        if (!s) return null;

        const entry = installationStatusLocal?.[s];
        const status = (entry?.status ?? null) as string | null;
        const enabled = entry?.enabled;

        return { status, enabled };
    };

    const hydrateInstallBadgesFromStatusMap = (
        map: Record<string, InstallationStatusEntry> | null | undefined,
    ) => {
        const nextInstalled: Record<string, boolean> = {};
        const nextQueued: Record<string, boolean> = {};

        const source = map ?? {};
        for (const [slug, entry] of Object.entries(source)) {
            if (!slug) continue;

            const enabled = entry?.enabled !== false;
            const status = (entry?.status ?? "").toString();

            if (!enabled) continue;

            if (status === "installed") nextInstalled[slug] = true;
            if (status === "requested" || status === "installing")
                nextQueued[slug] = true;
        }

        installedBySlug = { ...installedBySlug, ...nextInstalled };
        queuedBySlug = { ...queuedBySlug, ...nextQueued };
    };

    onMount(() => {
        hydrateInstallBadgesFromStatusMap(installationStatusLocal);
    });

    const installLabel = (pkg: MarketplacePackage) => {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return "Install";

        const known = getKnownStatus(slug);

        if (installingBySlug[slug]) return "Requesting…";
        if (known?.enabled !== false && known?.status === "installed")
            return "Installed";
        if (known?.enabled !== false && known?.status === "installing")
            return "Installing…";
        if (known?.enabled !== false && known?.status === "requested")
            return "Queued";
        if (known?.status === "failed") return "Retry install";
        if (known?.status === "disabled") return "Disabled";

        if (installedBySlug[slug]) return "Installed";
        if (queuedBySlug[slug]) return "Queued";

        return "Install";
    };

    const installDisabled = (pkg: MarketplacePackage) => {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return true;
        if (installingBySlug[slug]) return true;

        const known = getKnownStatus(slug);

        if (known?.enabled !== false && known?.status === "installed")
            return true;
        if (known?.enabled !== false && known?.status === "installing")
            return true;
        if (known?.enabled !== false && known?.status === "requested")
            return true;
        if (known?.status === "disabled") return true;

        // allow retry if failed
        return false;
    };

    const installTitle = (pkg: MarketplacePackage) => {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return "Missing package slug";

        const known = getKnownStatus(slug);

        if (known?.enabled !== false && known?.status === "installed")
            return "Already installed";
        if (known?.enabled !== false && known?.status === "installing")
            return "Installation is in progress";
        if (known?.enabled !== false && known?.status === "requested")
            return "Installation has been queued";
        if (known?.status === "failed")
            return "Previous install failed; click to retry";
        if (known?.status === "disabled") return "Installation is disabled";

        if (queuedBySlug[slug]) return "Installation queued";
        if (installingBySlug[slug]) return "Submitting install request";

        return "Install this package into your current organization";
    };

    const uninstallVisible = (pkg: MarketplacePackage) => {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return false;

        const known = getKnownStatus(slug);

        // Show uninstall only when it looks installed or in-progress for this tenant.
        if (known?.enabled !== false && known?.status === "installed")
            return true;
        if (known?.enabled !== false && known?.status === "installing")
            return true;
        if (known?.enabled !== false && known?.status === "requested")
            return true;

        if (installedBySlug[slug]) return true;
        if (queuedBySlug[slug]) return true;

        return false;
    };

    const uninstallDisabled = (pkg: MarketplacePackage) => {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return true;

        // Don’t allow uninstall while we’re actively submitting an install request from this UI.
        if (installingBySlug[slug]) return true;

        return false;
    };

    const uninstallTitle = (pkg: MarketplacePackage) => {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return "Missing package slug";
        if (installingBySlug[slug])
            return "Please wait for the install request to finish";

        return "Uninstall this package from your current organization (dev tool)";
    };

    async function refreshInstallationStatusOnce() {
        const res = await fetch("/marketplace/installations/status", {
            method: "GET",
            headers: { Accept: "application/json" },
        });

        const data = (await res.json().catch(() => null)) as any;

        if (!res.ok || !data || data.ok !== true) return null;

        const next = (data.installation_status ?? {}) as Record<
            string,
            InstallationStatusEntry
        >;

        installationStatusLocal = next;
        hydrateInstallBadgesFromStatusMap(next);
        return next;
    }

    async function pollInstallUntilSettled(slug: string) {
        const target = (slug ?? "").trim();
        if (!target) return;

        // Poll for up to ~30s
        for (let attempt = 0; attempt < 30; attempt++) {
            await new Promise((r) => setTimeout(r, 1000));

            const map = await refreshInstallationStatusOnce();
            if (!map) continue;

            const entry = map[target];
            const status = (entry?.status ?? "").toString();

            if (status === "installed") {
                installedBySlug = { ...installedBySlug, [target]: true };
                queuedBySlug = { ...queuedBySlug, [target]: false };
                installErrorsBySlug = { ...installErrorsBySlug, [target]: "" };
                return;
            }

            if (status === "failed") {
                queuedBySlug = { ...queuedBySlug, [target]: false };
                installedBySlug = { ...installedBySlug, [target]: false };

                const lastError = (entry?.last_error ?? "").toString().trim();
                const lastErrorAt = (entry?.last_error_at ?? "")
                    .toString()
                    .trim();

                const message = lastError
                    ? `Install failed: ${lastError}${lastErrorAt ? ` (at ${lastErrorAt})` : ""}`
                    : "Install failed (see Admin for details).";

                installErrorsBySlug = {
                    ...installErrorsBySlug,
                    [target]: message,
                };
                return;
            }

            if (status === "disabled") {
                queuedBySlug = { ...queuedBySlug, [target]: false };
                installedBySlug = { ...installedBySlug, [target]: false };
                return;
            }
        }
    }

    async function installPackage(pkg: MarketplacePackage) {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return;

        // If the server already knows it’s installed or in progress, don’t re-request.
        const known = getKnownStatus(slug);
        if (known?.enabled !== false && known?.status === "installed") return;
        if (known?.enabled !== false && known?.status === "installing") return;
        if (known?.enabled !== false && known?.status === "requested") return;

        if (installingBySlug[slug]) return;

        installingBySlug = { ...installingBySlug, [slug]: true };
        installErrorsBySlug = { ...installErrorsBySlug, [slug]: "" };

        try {
            const csrf = getCsrfToken();

            const res = await fetch("/marketplace/install", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({
                    slug,
                    version: pkg.version ?? undefined,
                }),
            });

            const data = (await res
                .json()
                .catch(() => null)) as InstallResponse | null;

            if (!res.ok) {
                const err =
                    (data as any)?.error ??
                    `Install failed (${res.status} ${res.statusText})`;
                installErrorsBySlug = { ...installErrorsBySlug, [slug]: err };
                return;
            }

            if (!data || (data as any).ok !== true) {
                const err = (data as any)?.error ?? "Install failed";
                installErrorsBySlug = { ...installErrorsBySlug, [slug]: err };
                return;
            }

            // Optimistic UI: show queued immediately, then poll until installed/failed.
            const status = (data as any).status;
            if (status === "installed") {
                installedBySlug = { ...installedBySlug, [slug]: true };
                queuedBySlug = { ...queuedBySlug, [slug]: false };
            } else {
                queuedBySlug = { ...queuedBySlug, [slug]: true };
            }

            await pollInstallUntilSettled(slug);
        } catch (_err) {
            installErrorsBySlug = {
                ...installErrorsBySlug,
                [slug]: "Install request failed (network error)",
            };
        } finally {
            installingBySlug = { ...installingBySlug, [slug]: false };
        }
    }

    type UninstallResponse =
        | {
              ok: true;
              directive_id: string;
              directive_status: string;
              directive_created?: boolean;
              enqueued: boolean;
              tenant: string;
              package: { slug: string; version?: string | null };
          }
        | { ok: false; error: string; [key: string]: unknown };

    async function uninstallPackageSlug(slug: string, purge: boolean) {
        const target = (slug ?? "").trim();
        if (!target) return;

        try {
            const csrf = getCsrfToken();

            const res = await fetch("/marketplace/uninstall", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({
                    slug: target,
                    purge,
                }),
            });

            const data = (await res
                .json()
                .catch(() => null)) as UninstallResponse | null;

            if (!res.ok) {
                const err =
                    (data as any)?.error ??
                    `Uninstall failed (${res.status} ${res.statusText})`;
                installErrorsBySlug = { ...installErrorsBySlug, [target]: err };
                return;
            }

            if (!data || (data as any).ok !== true) {
                const err = (data as any)?.error ?? "Uninstall failed";
                installErrorsBySlug = { ...installErrorsBySlug, [target]: err };
                return;
            }

            // Optimistic UI: clear local badges; then refresh status from server.
            queuedBySlug = { ...queuedBySlug, [target]: false };
            installedBySlug = { ...installedBySlug, [target]: false };

            // If the server is tracking install status per tenant, refresh it so "Install" becomes available.
            await refreshInstallationStatusOnce();
        } catch (_err) {
            installErrorsBySlug = {
                ...installErrorsBySlug,
                [target]: "Uninstall request failed (network error)",
            };
        }
    }

    function confirmAndUninstall(pkg: MarketplacePackage) {
        const slug = (pkg.slug ?? "").trim();
        if (!slug) return;

        const purge = window.confirm(
            "Also purge matching installed agent templates from this tenant?\n\nThis is best-effort and only deletes agents that match the package includes signature (name + system_prompt).",
        );

        void uninstallPackageSlug(slug, purge);
    }
</script>

<svelte:head>
    <title>{title} • FleetPrompt</title>
</svelte:head>

<AppShell
    {title}
    {subtitle}
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
            href="/dashboard"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Dashboard
        </a>

        <a
            href="/admin/tenant"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
            title="AshAdmin runs on LiveView; tenant selection is required to browse tenant-scoped resources."
        >
            Admin
        </a>
    </svelte:fragment>

    <!-- Search + filters (GET /marketplace?q=...&category=...&pricing=...&tier=...) -->
    <section
        class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8"
    >
        <div class="flex flex-col gap-6">
            <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                    <h2
                        class="text-2xl sm:text-3xl font-semibold tracking-tight"
                    >
                        Marketplace
                    </h2>
                    <p class="mt-2 text-sm sm:text-base text-muted-foreground">
                        Browse packages you can install into your organization.
                        Search and filters are powered by the backend.
                    </p>
                </div>

                <div class="hidden sm:flex items-center gap-2">
                    <a
                        use:inertia
                        href="/chat"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
                    >
                        Chat
                    </a>
                    <a
                        use:inertia
                        href="/marketplace"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
                        title="Clear filters"
                    >
                        Reset
                    </a>
                </div>
            </div>

            <form
                method="GET"
                action="/marketplace"
                class="grid grid-cols-1 lg:grid-cols-12 gap-3"
            >
                <div class="lg:col-span-5">
                    <label for="q" class="sr-only">Search</label>
                    <input
                        id="q"
                        name="q"
                        value={filters.query ?? ""}
                        placeholder="Search packages…"
                        class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                    />
                </div>

                <div class="lg:col-span-3">
                    <label for="category" class="sr-only">Category</label>
                    <select
                        id="category"
                        name="category"
                        class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                    >
                        {#each categories as c}
                            <option
                                value={c.value}
                                selected={(filters.category ?? "") === c.value}
                            >
                                {c.label}
                            </option>
                        {/each}
                    </select>
                </div>

                <div class="lg:col-span-2">
                    <label for="pricing" class="sr-only">Pricing</label>
                    <select
                        id="pricing"
                        name="pricing"
                        class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                    >
                        {#each pricingModels as p}
                            <option
                                value={p.value}
                                selected={(filters.pricing ?? "") === p.value}
                            >
                                {p.label}
                            </option>
                        {/each}
                    </select>
                </div>

                <div class="lg:col-span-2">
                    <label for="tier" class="sr-only">Tier</label>
                    <select
                        id="tier"
                        name="tier"
                        class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                    >
                        {#each tiers as t}
                            <option
                                value={t.value}
                                selected={(filters.tier ?? "") === t.value}
                            >
                                {t.label}
                            </option>
                        {/each}
                    </select>
                </div>

                <div
                    class="lg:col-span-12 flex flex-wrap items-center justify-between gap-3 pt-1"
                >
                    <div class="text-xs text-muted-foreground">
                        Showing <span class="font-medium text-foreground"
                            >{packages.length}</span
                        >
                        packages
                        {#if featured.length > 0}
                            • <span class="font-medium text-foreground"
                                >{featured.length}</span
                            > featured
                        {/if}
                    </div>

                    <div class="flex items-center gap-2">
                        <button
                            type="submit"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-4"
                        >
                            Apply
                        </button>

                        <a
                            use:inertia
                            href="/marketplace"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-4"
                        >
                            Clear
                        </a>
                    </div>
                </div>
            </form>
        </div>
    </section>

    <!-- Featured -->
    {#if featured.length > 0 && !(filters.query || filters.category || filters.pricing || filters.tier)}
        <section class="mt-8">
            <div class="flex items-center justify-between">
                <h3 class="text-lg font-semibold">Featured</h3>
                <span class="text-xs text-muted-foreground">
                    Curated picks
                </span>
            </div>

            <div
                class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
            >
                {#each featured as pkg (pkg.id)}
                    <div
                        class="rounded-2xl border border-border bg-card text-card-foreground p-5"
                    >
                        <div class="flex items-start justify-between gap-3">
                            <div class="min-w-0">
                                <div class="flex items-center gap-3">
                                    {#if pkg.icon_url}
                                        <img
                                            src={pkg.icon_url}
                                            alt={pkg.name}
                                            class="h-10 w-10 rounded-lg border border-border"
                                        />
                                    {:else}
                                        <div
                                            class="h-10 w-10 rounded-lg border border-border bg-muted flex items-center justify-center text-xs text-muted-foreground"
                                        >
                                            FP
                                        </div>
                                    {/if}

                                    <div class="min-w-0">
                                        <div class="flex items-center gap-2">
                                            <div class="font-semibold truncate">
                                                {pkg.name}
                                            </div>
                                            {#if pkg.is_verified}
                                                <span
                                                    class="text-[10px] rounded-full border border-border px-2 py-0.5 text-muted-foreground"
                                                >
                                                    Verified
                                                </span>
                                            {/if}
                                        </div>
                                        <div
                                            class="text-xs text-muted-foreground truncate"
                                        >
                                            {pkg.category ?? "—"}
                                        </div>
                                    </div>
                                </div>

                                {#if pkg.description}
                                    <p
                                        class="mt-3 text-sm text-muted-foreground line-clamp-3"
                                    >
                                        {pkg.description}
                                    </p>
                                {/if}
                            </div>

                            <div class="text-right flex-shrink-0">
                                <div class="text-xs text-muted-foreground">
                                    Pricing
                                </div>
                                <div
                                    class="text-sm font-medium text-foreground"
                                >
                                    {formatPricing(pkg)}
                                </div>
                            </div>
                        </div>

                        <div
                            class="mt-4 flex items-center justify-between text-xs text-muted-foreground"
                        >
                            <div>
                                {#if formatRating(pkg.rating_avg) !== null}
                                    <span class="font-medium text-foreground"
                                        >{formatRating(pkg.rating_avg)}</span
                                    >
                                    <span> ({pkg.rating_count ?? 0})</span>
                                {:else}
                                    <span>Unrated</span>
                                {/if}
                            </div>
                            <div>
                                <span class="font-medium text-foreground"
                                    >{formatInstalls(pkg.install_count)}</span
                                >
                                <span> installs</span>
                            </div>
                        </div>

                        <div class="mt-4 flex items-center justify-end gap-2">
                            {#if uninstallVisible(pkg)}
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:pointer-events-none"
                                    title={uninstallTitle(pkg)}
                                    disabled={uninstallDisabled(pkg)}
                                    on:click={() => confirmAndUninstall(pkg)}
                                >
                                    Uninstall
                                </button>
                            {/if}

                            <div class="flex flex-col items-end gap-1">
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:pointer-events-none"
                                    title={installTitle(pkg)}
                                    disabled={installDisabled(pkg)}
                                    on:click={() => installPackage(pkg)}
                                >
                                    {installLabel(pkg)}
                                </button>

                                {#if installErrorsBySlug[pkg.slug]}
                                    <div class="text-xs text-red-600">
                                        {installErrorsBySlug[pkg.slug]}
                                    </div>
                                {/if}
                            </div>
                        </div>
                    </div>
                {/each}
            </div>
        </section>
    {/if}

    <!-- Results -->
    <section class="mt-8">
        <div class="flex items-center justify-between">
            <h3 class="text-lg font-semibold">All packages</h3>
            <a
                href="/admin/tenant"
                class="text-xs text-muted-foreground hover:text-foreground transition-colors"
                title="Tenant selection is required for browsing tenant-scoped resources in AshAdmin."
            >
                Select tenant for Admin →
            </a>
        </div>

        {#if packages.length === 0}
            <div class="mt-4 rounded-2xl border border-border bg-muted/20 p-6">
                <div class="font-medium">No results</div>
                <p class="mt-1 text-sm text-muted-foreground">
                    Try adjusting your search or clearing filters. If this is
                    your first run, make sure seeds and migrations have been
                    applied.
                </p>
                <div class="mt-4 flex flex-wrap gap-2">
                    <a
                        use:inertia
                        href="/marketplace"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
                    >
                        Clear filters
                    </a>
                    <a
                        use:inertia
                        href="/dashboard"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   border border-border bg-background hover:bg-muted h-9 px-3"
                    >
                        Back to Dashboard
                    </a>
                </div>
            </div>
        {:else}
            <div
                class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
            >
                {#each packages as pkg (pkg.id)}
                    <div
                        class="rounded-2xl border border-border bg-card text-card-foreground p-5"
                    >
                        <div class="flex items-start justify-between gap-3">
                            <div class="min-w-0">
                                <div class="flex items-center gap-3">
                                    {#if pkg.icon_url}
                                        <img
                                            src={pkg.icon_url}
                                            alt={pkg.name}
                                            class="h-10 w-10 rounded-lg border border-border"
                                        />
                                    {:else}
                                        <div
                                            class="h-10 w-10 rounded-lg border border-border bg-muted flex items-center justify-center text-xs text-muted-foreground"
                                        >
                                            FP
                                        </div>
                                    {/if}

                                    <div class="min-w-0">
                                        <div class="flex items-center gap-2">
                                            <div class="font-semibold truncate">
                                                {pkg.name}
                                            </div>
                                            {#if pkg.is_verified}
                                                <span
                                                    class="text-[10px] rounded-full border border-border px-2 py-0.5 text-muted-foreground"
                                                >
                                                    Verified
                                                </span>
                                            {/if}
                                        </div>
                                        <div
                                            class="text-xs text-muted-foreground truncate"
                                        >
                                            {pkg.category ?? "—"}
                                        </div>
                                    </div>
                                </div>

                                {#if pkg.description}
                                    <p
                                        class="mt-3 text-sm text-muted-foreground line-clamp-3"
                                    >
                                        {pkg.description}
                                    </p>
                                {/if}
                            </div>

                            <div class="text-right flex-shrink-0">
                                <div class="text-xs text-muted-foreground">
                                    Pricing
                                </div>
                                <div
                                    class="text-sm font-medium text-foreground"
                                >
                                    {formatPricing(pkg)}
                                </div>
                            </div>
                        </div>

                        <div
                            class="mt-4 flex items-center justify-between text-xs text-muted-foreground"
                        >
                            <div>
                                {#if formatRating(pkg.rating_avg) !== null}
                                    <span class="font-medium text-foreground"
                                        >{formatRating(pkg.rating_avg)}</span
                                    >
                                    <span> ({pkg.rating_count ?? 0})</span>
                                {:else}
                                    <span>Unrated</span>
                                {/if}
                            </div>
                            <div>
                                <span class="font-medium text-foreground"
                                    >{formatInstalls(pkg.install_count)}</span
                                >
                                <span> installs</span>
                            </div>
                        </div>

                        <div class="mt-4 flex items-center justify-end gap-2">
                            {#if uninstallVisible(pkg)}
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:pointer-events-none"
                                    title={uninstallTitle(pkg)}
                                    disabled={uninstallDisabled(pkg)}
                                    on:click={() => confirmAndUninstall(pkg)}
                                >
                                    Uninstall
                                </button>
                            {/if}

                            <div class="flex flex-col items-end gap-1">
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:pointer-events-none"
                                    title={installTitle(pkg)}
                                    disabled={installDisabled(pkg)}
                                    on:click={() => installPackage(pkg)}
                                >
                                    {installLabel(pkg)}
                                </button>

                                {#if installErrorsBySlug[pkg.slug]}
                                    <div class="text-xs text-red-600">
                                        {installErrorsBySlug[pkg.slug]}
                                    </div>
                                {/if}
                            </div>
                        </div>
                    </div>
                {/each}
            </div>
        {/if}
    </section>
</AppShell>
