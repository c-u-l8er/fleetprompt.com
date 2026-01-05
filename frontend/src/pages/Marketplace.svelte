<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    type PricingModel = "free" | "freemium" | "paid" | "revenue_share";
    type Tier = "free" | "pro" | "enterprise";

    type MarketplacePackage = {
        id: string;
        name: string;
        slug: string;
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
</script>

<svelte:head>
    <title>{title} • FleetPrompt</title>
</svelte:head>

<AppShell {title} {subtitle} showAdminLink={true}>
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
                            <button
                                type="button"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 px-3"
                                title="Install flow lands in Phase 2"
                                disabled
                            >
                                Install
                            </button>
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
                            <button
                                type="button"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                       border border-border bg-background hover:bg-muted h-9 px-3"
                                title="Install flow lands in Phase 2"
                                disabled
                            >
                                Install
                            </button>
                        </div>
                    </div>
                {/each}
            </div>
        {/if}
    </section>
</AppShell>
