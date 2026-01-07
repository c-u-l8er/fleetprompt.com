<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    type CategoryKey = "announcements" | "support" | "showcase" | "design";
    type TabKey = "all" | CategoryKey;

    type ForumCategory = {
        key: CategoryKey;
        name: string;
        description?: string | null;
        is_readonly?: boolean | null;
    };

    type ForumThread = {
        id: string;
        category_key: CategoryKey;
        title: string;
        excerpt: string;
        tags: string[];
        author_name: string;
        created_at: string; // ISO
        last_activity_at: string; // ISO
        reply_count: number;
        reaction_count: number;
        is_pinned?: boolean;
        is_locked?: boolean;
    };

    export let title: string = "Forums";
    export let subtitle: string =
        "Agent-native discussions (mocked UI). Ready for Phase 6 wiring.";

    // Shared props (provided globally by the backend via Inertia shared props)
    export let user: {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    } | null = null;

    // Tenant context
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

    // -------------------------
    // Tenant data (from backend; Phase 2C wiring)
    // -------------------------
    export let categories: Array<{
        id: string;
        slug: string;
        name: string;
        description?: string | null;
        status?: string | null;
    }> = [];
    // -------------------------
    // Mock data (temporary)
    // -------------------------
    const mockCategories: ForumCategory[] = [
        {
            key: "announcements",
            name: "Announcements",
            description: "Product updates and roadmap notes.",
            is_readonly: true,
        },
        {
            key: "support",
            name: "Support",
            description: "Help, troubleshooting, and how-to questions.",
        },
        {
            key: "showcase",
            name: "Showcase",
            description: "Share packages, agents, and workflows you’ve built.",
        },
        {
            key: "design",
            name: "Design & UX",
            description: "UI patterns, accessibility, and interaction design.",
        },
    ];

    const mockThreads: ForumThread[] = [
        {
            id: "t_001",
            category_key: "announcements",
            title: "Welcome to FleetPrompt Forums (placeholder)",
            excerpt:
                "This is a mocked Forums UI so navigation + layout are ready before Phase 6. Data + actions will be wired later.",
            tags: ["meta", "roadmap"],
            author_name: "FleetPrompt Team",
            created_at: "2026-01-05T18:00:00.000Z",
            last_activity_at: "2026-01-06T20:10:00.000Z",
            reply_count: 3,
            reaction_count: 14,
            is_pinned: true,
            is_locked: true,
        },
        {
            id: "t_002",
            category_key: "support",
            title: "How should tenant context affect forum visibility?",
            excerpt:
                "Should forums be tenant-scoped by default? If we add public forums later, how does that interact with org schemas and membership roles?",
            tags: ["multitenancy", "auth", "policy"],
            author_name: "demo@fleetprompt.com",
            created_at: "2026-01-06T10:25:00.000Z",
            last_activity_at: "2026-01-06T19:03:00.000Z",
            reply_count: 8,
            reaction_count: 5,
        },
        {
            id: "t_003",
            category_key: "design",
            title: "Forums UX framework: threads, posts, and agent participation",
            excerpt:
                "Proposing a consistent UX baseline: category index → thread list → thread view with posts, reactions, and an auditable agent interaction timeline (signals + directives).",
            tags: ["ux", "agents", "signals"],
            author_name: "travis",
            created_at: "2026-01-06T12:00:00.000Z",
            last_activity_at: "2026-01-06T18:45:00.000Z",
            reply_count: 12,
            reaction_count: 21,
        },
        {
            id: "t_004",
            category_key: "showcase",
            title: "Showcase: Mattermost Daily Ops Digest (lighthouse package)",
            excerpt:
                "Share the install + config flow, what signals it consumes/emits, and what the operator experience feels like end-to-end.",
            tags: ["packages", "mattermost", "lighthouse"],
            author_name: "FleetPrompt Team",
            created_at: "2026-01-06T14:15:00.000Z",
            last_activity_at: "2026-01-06T16:10:00.000Z",
            reply_count: 4,
            reaction_count: 9,
        },
    ];

    // -------------------------
    // UI state (client-side only)
    // -------------------------
    const tabs: Array<{ key: TabKey; label: string }> = [
        { key: "all", label: "All" },
        { key: "announcements", label: "Announcements" },
        { key: "support", label: "Support" },
        { key: "showcase", label: "Showcase" },
        { key: "design", label: "Design & UX" },
    ];

    let activeTab: TabKey = "all";
    let query = "";

    const normalize = (s: string) => (s ?? "").trim().toLowerCase();

    const formatDate = (iso: string) => {
        try {
            const d = new Date(iso);
            return d.toLocaleString(undefined, {
                year: "numeric",
                month: "short",
                day: "2-digit",
            });
        } catch {
            return iso;
        }
    };

    const formatRelative = (iso: string) => {
        try {
            const d = new Date(iso).getTime();
            const now = Date.now();
            const delta = Math.max(0, now - d);

            const min = Math.floor(delta / 60000);
            if (min < 60) return `${min}m ago`;

            const hr = Math.floor(min / 60);
            if (hr < 24) return `${hr}h ago`;

            const days = Math.floor(hr / 24);
            return `${days}d ago`;
        } catch {
            return iso;
        }
    };

    const categoryByKey = (key: string) =>
        mockCategories.find((c) => c.key === key) ?? null;

    const filteredThreads = () => {
        const q = normalize(query);

        return mockThreads
            .filter((t) => {
                if (activeTab === "all") return true;
                return t.category_key === activeTab;
            })
            .filter((t) => {
                if (!q) return true;
                const haystack = normalize(
                    [
                        t.title,
                        t.excerpt,
                        t.author_name,
                        t.category_key,
                        ...(t.tags ?? []),
                    ].join(" "),
                );
                return haystack.includes(q);
            })
            .sort((a, b) => {
                // Pinned first, then by last activity
                const ap = a.is_pinned ? 1 : 0;
                const bp = b.is_pinned ? 1 : 0;
                if (ap !== bp) return bp - ap;

                return (
                    new Date(b.last_activity_at).getTime() -
                    new Date(a.last_activity_at).getTime()
                );
            });
    };

    const canCreateThread = () => {
        // For now, just require a signed-in user AND a tenant context.
        // Server must enforce org membership + policies.
        return !!user?.id && !!tenant_schema;
    };

    const canManageCategories = () => {
        // Categories are admin-managed. This is a UX gate; server must enforce.
        const role = (user?.role ?? "").toString();
        return (
            !!user?.id &&
            !!tenant_schema &&
            (role === "owner" || role === "admin")
        );
    };

    function selectTab(key: TabKey) {
        activeTab = key;
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
            use:inertia
            href="/marketplace"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
        >
            Marketplace
        </a>

        <a
            use:inertia
            href={canManageCategories() ? "/forums/categories/new" : "/forums"}
            class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3 ${
                 canManageCategories() ? "" : "opacity-60 pointer-events-none"
             }`}
            aria-disabled={!canManageCategories()}
            title={canManageCategories()
                ? "Create a new category (Phase 2C)"
                : "Only org admins can create categories. Make sure you’ve selected an org/tenant."}
        >
            New category
        </a>

        <a
            use:inertia
            href={canCreateThread() ? "/forums/new" : "/forums"}
            class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3 ${
                 canCreateThread() ? "" : "opacity-60 pointer-events-none"
             }`}
            aria-disabled={!canCreateThread()}
            title={canCreateThread()
                ? "Create a new thread (mocked)"
                : "Sign in and select an org/tenant to create threads (Phase 6 will enforce policies)."}
        >
            New thread
        </a>
    </svelte:fragment>

    <!-- Top info / architecture callout -->
    <section
        class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8"
    >
        <div class="flex flex-col gap-4">
            <div class="flex flex-col gap-2">
                <h2 class="text-xl font-semibold tracking-tight">
                    Forums UI foundation (mock)
                </h2>
                <p class="text-sm text-muted-foreground max-w-3xl">
                    This page is intentionally mocked to lock in the UX/UI
                    framework early: categories → thread list → (next) thread
                    view. In Phase 6, the data model becomes Ash resources and
                    all mutations become directives with an auditable signal
                    trail.
                </p>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div class="rounded-xl border border-border bg-muted/20 p-4">
                    <div
                        class="text-xs font-semibold uppercase tracking-wide text-muted-foreground"
                    >
                        UX principle
                    </div>
                    <div class="mt-2 text-sm">
                        Agents are first-class participants, but they never
                        cause side effects without directives.
                    </div>
                </div>

                <div class="rounded-xl border border-border bg-muted/20 p-4">
                    <div
                        class="text-xs font-semibold uppercase tracking-wide text-muted-foreground"
                    >
                        Product surface
                    </div>
                    <div class="mt-2 text-sm">
                        Every thread/post should expose an audit timeline
                        (signals + directives) as a user-visible feature.
                    </div>
                </div>

                <div class="rounded-xl border border-border bg-muted/20 p-4">
                    <div
                        class="text-xs font-semibold uppercase tracking-wide text-muted-foreground"
                    >
                        Today
                    </div>
                    <div class="mt-2 text-sm">
                        UI only: mocked list + filters. Next: add `/forums/:id`
                        and wire to Phase 6 resources.
                    </div>
                </div>
            </div>

            {#if !tenant_schema}
                <div
                    class="rounded-xl border border-primary/30 bg-primary/10 p-4 text-sm"
                >
                    <div class="font-medium">Tenant context not selected</div>
                    <div class="mt-1 text-muted-foreground">
                        In Phase 6, forums will be tenant-scoped by default.
                        Select an org/tenant to make “create thread” and
                        tenant-specific browsing meaningful.
                        <a
                            href="/admin/tenant"
                            class="ml-1 underline hover:text-foreground transition-colors"
                        >
                            Select tenant
                        </a>
                    </div>
                </div>
            {/if}
        </div>
    </section>

    <!-- Tenant categories (Phase 2C) -->
    <section
        class="mt-6 rounded-2xl border border-border bg-card text-card-foreground p-4 sm:p-6"
    >
        <div class="flex items-center justify-between gap-3">
            <div>
                <h2 class="text-lg font-semibold tracking-tight">Categories</h2>
                <p class="mt-1 text-sm text-muted-foreground">
                    Tenant-scoped categories (real data when configured).
                </p>
            </div>

            <a
                use:inertia
                href={canManageCategories()
                    ? "/forums/categories/new"
                    : "/forums"}
                class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-9 px-3 ${
                     canManageCategories()
                         ? ""
                         : "opacity-60 pointer-events-none"
                 }`}
                aria-disabled={!canManageCategories()}
                title={canManageCategories()
                    ? "Create a new category"
                    : "Only org admins can create categories."}
            >
                New category
            </a>
        </div>

        {#if categories && categories.length > 0}
            <div
                class="mt-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3"
            >
                {#each categories as cat (cat.id)}
                    <a
                        use:inertia
                        href={"/forums/c/" + cat.slug}
                        class="rounded-xl border border-border bg-background p-4 hover:bg-muted/20 transition-colors"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <div class="min-w-0">
                                <div class="font-medium truncate">
                                    {cat.name}
                                </div>
                                {#if cat.description}
                                    <div
                                        class="mt-1 text-sm text-muted-foreground line-clamp-2"
                                    >
                                        {cat.description}
                                    </div>
                                {:else}
                                    <div
                                        class="mt-1 text-sm text-muted-foreground"
                                    >
                                        No description
                                    </div>
                                {/if}
                            </div>

                            {#if cat.status && cat.status !== "active"}
                                <span
                                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px] font-semibold text-muted-foreground"
                                >
                                    {cat.status}
                                </span>
                            {/if}
                        </div>
                    </a>
                {/each}
            </div>
        {:else}
            <div class="mt-4 rounded-xl border border-border bg-muted/10 p-5">
                <div class="text-sm font-medium">No categories yet</div>
                <div class="mt-1 text-sm text-muted-foreground">
                    Create your first category to organize threads.
                </div>
            </div>
        {/if}
    </section>

    <!-- Tabs + search -->
    <section
        class="mt-6 rounded-2xl border border-border bg-card text-card-foreground p-4 sm:p-6"
    >
        <div class="flex flex-col gap-4">
            <div
                class="flex flex-col md:flex-row md:items-center md:justify-between gap-3"
            >
                <div class="flex flex-wrap items-center gap-2">
                    {#each tabs as tab (tab.key)}
                        <button
                            type="button"
                            class={`inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors ${
                                activeTab === tab.key
                                    ? "bg-muted text-foreground"
                                    : "text-muted-foreground hover:text-foreground hover:bg-muted/60"
                            }`}
                            on:click={() => selectTab(tab.key)}
                            aria-pressed={activeTab === tab.key}
                        >
                            {tab.label}
                        </button>
                    {/each}
                </div>

                <div class="flex items-center gap-2">
                    <label class="sr-only" for="forum_search"
                        >Search threads</label
                    >
                    <input
                        id="forum_search"
                        type="search"
                        bind:value={query}
                        placeholder="Search threads…"
                        class="h-10 w-full md:w-80 rounded-md border border-border bg-background px-3 text-sm"
                    />
                    <button
                        type="button"
                        class="h-10 rounded-md border border-border bg-background px-3 text-sm font-medium
                               hover:bg-muted transition-colors"
                        on:click={() => (query = "")}
                        disabled={!query.trim()}
                        title="Clear search"
                    >
                        Clear
                    </button>
                </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-12 gap-4">
                <!-- Thread list -->
                <div class="lg:col-span-8">
                    <div class="flex items-center justify-between">
                        <div class="text-sm text-muted-foreground">
                            Showing <span class="font-medium text-foreground"
                                >{filteredThreads().length}</span
                            >
                            thread{filteredThreads().length === 1 ? "" : "s"}
                        </div>

                        <div class="text-sm text-muted-foreground">
                            Sort: <span class="text-foreground font-medium"
                                >Pinned + latest activity</span
                            >
                        </div>
                    </div>

                    <div class="mt-3 space-y-3">
                        {#if filteredThreads().length === 0}
                            <div
                                class="rounded-xl border border-border bg-muted/10 p-6 text-center"
                            >
                                <div class="font-medium">No threads found</div>
                                <div class="mt-1 text-sm text-muted-foreground">
                                    Try a different search or switch categories.
                                </div>
                            </div>
                        {:else}
                            {#each filteredThreads() as thread (thread.id)}
                                <article
                                    class="rounded-xl border border-border bg-background p-4 sm:p-5 hover:bg-muted/20 transition-colors"
                                >
                                    <div
                                        class="flex items-start justify-between gap-3"
                                    >
                                        <div class="min-w-0">
                                            <div
                                                class="flex flex-wrap items-center gap-2"
                                            >
                                                {#if thread.is_pinned}
                                                    <span
                                                        class="inline-flex items-center rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px] font-semibold text-muted-foreground"
                                                    >
                                                        PINNED
                                                    </span>
                                                {/if}
                                                {#if thread.is_locked}
                                                    <span
                                                        class="inline-flex items-center rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px] font-semibold text-muted-foreground"
                                                    >
                                                        LOCKED
                                                    </span>
                                                {/if}

                                                <a
                                                    use:inertia
                                                    href={"/forums/c/" +
                                                        thread.category_key}
                                                    class="text-xs text-muted-foreground hover:text-foreground transition-colors"
                                                    title="Open category"
                                                >
                                                    {categoryByKey(
                                                        thread.category_key,
                                                    )?.name ??
                                                        thread.category_key}
                                                </a>
                                            </div>

                                            <h3
                                                class="mt-1 text-base sm:text-lg font-semibold leading-snug truncate"
                                            >
                                                <a
                                                    use:inertia
                                                    href={"/forums/t/" +
                                                        thread.id}
                                                    class="hover:underline underline-offset-4"
                                                    title="Open thread"
                                                >
                                                    {thread.title}
                                                </a>
                                            </h3>

                                            <p
                                                class="mt-1 text-sm text-muted-foreground"
                                            >
                                                {thread.excerpt}
                                            </p>

                                            <div
                                                class="mt-3 flex flex-wrap items-center gap-2"
                                            >
                                                {#each thread.tags as tag (tag)}
                                                    <span
                                                        class="inline-flex items-center rounded-md bg-muted px-2 py-1 text-xs text-muted-foreground"
                                                    >
                                                        #{tag}
                                                    </span>
                                                {/each}
                                            </div>
                                        </div>

                                        <div
                                            class="flex flex-col items-end text-xs text-muted-foreground gap-1 shrink-0"
                                        >
                                            <div>
                                                Active <span
                                                    class="font-medium text-foreground"
                                                    >{formatRelative(
                                                        thread.last_activity_at,
                                                    )}</span
                                                >
                                            </div>
                                            <div>
                                                Created {formatDate(
                                                    thread.created_at,
                                                )}
                                            </div>
                                            <div
                                                class="mt-1 flex items-center gap-3"
                                            >
                                                <span>
                                                    <span
                                                        class="font-medium text-foreground"
                                                        >{thread.reply_count}</span
                                                    > replies
                                                </span>
                                                <span>
                                                    <span
                                                        class="font-medium text-foreground"
                                                        >{thread.reaction_count}</span
                                                    > reactions
                                                </span>
                                            </div>
                                        </div>
                                    </div>

                                    <div
                                        class="mt-4 flex items-center justify-between gap-3"
                                    >
                                        <div
                                            class="text-xs text-muted-foreground"
                                        >
                                            Started by <span
                                                class="text-foreground font-medium"
                                                >{thread.author_name}</span
                                            >
                                        </div>

                                        <!-- Placeholder actions: Phase 6 will route to /forums/threads/:id -->
                                        <div class="flex items-center gap-2">
                                            <a
                                                use:inertia
                                                href={"/forums/t/" + thread.id}
                                                class="h-9 inline-flex items-center rounded-md border border-border bg-background px-3 text-sm font-medium
                                                       hover:bg-muted transition-colors"
                                                title="Open thread"
                                            >
                                                Open
                                            </a>
                                            <button
                                                type="button"
                                                class="h-9 rounded-md border border-border bg-background px-3 text-sm font-medium
                                                       hover:bg-muted transition-colors disabled:opacity-60 disabled:pointer-events-none"
                                                disabled={true}
                                                title="Reactions will be directive-backed in Phase 6"
                                            >
                                                React
                                            </button>
                                        </div>
                                    </div>
                                </article>
                            {/each}
                        {/if}
                    </div>
                </div>

                <!-- Sidebar: categories -->
                <aside class="lg:col-span-4">
                    <div
                        class="rounded-xl border border-border bg-background p-4 sm:p-5"
                    >
                        <h3 class="text-sm font-semibold tracking-tight">
                            Categories
                        </h3>
                        <p class="mt-1 text-xs text-muted-foreground">
                            Phase 6 will back these with `Forum.Category`
                            resources.
                        </p>

                        <div class="mt-4 space-y-2">
                            {#each categories as c (c.key)}
                                <button
                                    type="button"
                                    class={`w-full text-left rounded-lg border px-3 py-3 transition-colors ${
                                        activeTab === c.key
                                            ? "border-primary/40 bg-primary/10"
                                            : "border-border bg-muted/10 hover:bg-muted/20"
                                    }`}
                                    on:click={() => selectTab(c.key)}
                                >
                                    <div
                                        class="flex items-center justify-between gap-3"
                                    >
                                        <div class="min-w-0">
                                            <div class="font-medium truncate">
                                                {c.name}
                                            </div>
                                            {#if c.description}
                                                <div
                                                    class="mt-0.5 text-xs text-muted-foreground"
                                                >
                                                    {c.description}
                                                </div>
                                            {/if}
                                        </div>

                                        {#if c.is_readonly}
                                            <span
                                                class="shrink-0 inline-flex items-center rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px] font-semibold text-muted-foreground"
                                            >
                                                READ-ONLY
                                            </span>
                                        {/if}
                                    </div>
                                </button>
                            {/each}

                            <button
                                type="button"
                                class={`w-full text-left rounded-lg border px-3 py-3 transition-colors ${
                                    activeTab === "all"
                                        ? "border-primary/40 bg-primary/10"
                                        : "border-border bg-muted/10 hover:bg-muted/20"
                                }`}
                                on:click={() => selectTab("all")}
                            >
                                <div class="font-medium">All threads</div>
                                <div
                                    class="mt-0.5 text-xs text-muted-foreground"
                                >
                                    Show everything across categories.
                                </div>
                            </button>
                        </div>
                    </div>

                    <div
                        class="mt-4 rounded-xl border border-border bg-muted/10 p-4 sm:p-5"
                    >
                        <h3 class="text-sm font-semibold tracking-tight">
                            What gets built later (Phase 6)
                        </h3>
                        <ul
                            class="mt-3 space-y-2 text-sm text-muted-foreground list-disc pl-5"
                        >
                            <li>
                                Thread page: posts + reactions + moderation
                                queue.
                            </li>
                            <li>
                                Agent participation UI (assist, suggest,
                                escalate).
                            </li>
                            <li>
                                Audit timeline surfaced in-product (signals +
                                directives).
                            </li>
                            <li>
                                Abuse controls: rate limiting, flags, and safe
                                defaults.
                            </li>
                        </ul>

                        <div class="mt-4 flex flex-wrap gap-2">
                            <a
                                use:inertia
                                href="/chat"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                       border border-border bg-background hover:bg-muted h-9 px-3"
                            >
                                Open Chat
                            </a>

                            <a
                                use:inertia
                                href="/marketplace"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                       border border-border bg-background hover:bg-muted h-9 px-3"
                            >
                                View Marketplace
                            </a>

                            <a
                                href="/admin/tenant"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                       bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
                                title="AshAdmin runs on LiveView; tenant selection is required to browse tenant-scoped resources."
                            >
                                Admin
                            </a>
                        </div>
                    </div>
                </aside>
            </div>
        </div>
    </section>
</AppShell>
