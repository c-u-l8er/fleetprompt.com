<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    type ForumCategory = {
        id: string;
        slug: string;
        name: string;
        description?: string | null;
        is_locked?: boolean | null;
        stats?: {
            threads?: number | null;
            posts?: number | null;
            last_activity_at?: string | null;
        } | null;
    };

    type ForumThread = {
        id: string;
        title: string;
        excerpt?: string | null;
        is_pinned?: boolean | null;
        is_locked?: boolean | null;
        tags?: string[] | null;
        created_at?: string | null;
        updated_at?: string | null;
        author?: {
            id?: string | null;
            name?: string | null;
        } | null;
        stats?: {
            replies?: number | null;
            views?: number | null;
            reactions?: number | null;
        } | null;
    };

    // Page props (mock-friendly; backend can replace later)
    export let title: string = "Forums";
    export let subtitle: string = "Category";

    export let category: ForumCategory = {
        id: "cat_mock_general",
        slug: "general",
        name: "General",
        description: "Product discussion, questions, and announcements.",
        is_locked: false,
        stats: {
            threads: 12,
            posts: 84,
            last_activity_at: new Date(
                Date.now() - 1000 * 60 * 12,
            ).toISOString(),
        },
    };

    export let threads: ForumThread[] = [
        {
            id: "thr_mock_001",
            title: "Welcome to FleetPrompt Forums (Mock)",
            excerpt:
                "This is a placeholder thread to lock down the UX/UI skeleton before Phase 6 lands.",
            is_pinned: true,
            is_locked: false,
            tags: ["announcement", "meta"],
            created_at: new Date(
                Date.now() - 1000 * 60 * 60 * 24 * 7,
            ).toISOString(),
            updated_at: new Date(Date.now() - 1000 * 60 * 20).toISOString(),
            author: { id: "usr_mock_admin", name: "FleetPrompt Team" },
            stats: { replies: 4, views: 128, reactions: 9 },
        },
        {
            id: "thr_mock_002",
            title: "How should agents participate in threads?",
            excerpt:
                "Brainstorming: agent personas, disclosure, permissions, and directive-backed actions.",
            is_pinned: false,
            is_locked: false,
            tags: ["agents", "design"],
            created_at: new Date(
                Date.now() - 1000 * 60 * 60 * 24 * 3,
            ).toISOString(),
            updated_at: new Date(Date.now() - 1000 * 60 * 60 * 4).toISOString(),
            author: { id: "usr_mock_001", name: "You" },
            stats: { replies: 12, views: 412, reactions: 21 },
        },
        {
            id: "thr_mock_003",
            title: "Roadmap feedback: Signals + Directives UX",
            excerpt:
                "What surfaces do you need to trust automation? Audit trail, replay, and safe retries.",
            is_pinned: false,
            is_locked: true,
            tags: ["signals", "directives", "ux"],
            created_at: new Date(
                Date.now() - 1000 * 60 * 60 * 24 * 2,
            ).toISOString(),
            updated_at: new Date(
                Date.now() - 1000 * 60 * 60 * 30,
            ).toISOString(),
            author: { id: "usr_mock_002", name: "Operator" },
            stats: { replies: 2, views: 97, reactions: 3 },
        },
    ];

    // Shared props (provided globally by the backend via shared Inertia props)
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
        name: string;
        slug: string;
    }> | null = null;

    export let current_organization: {
        id: string;
        name: string;
        slug: string;
    } | null = null;

    // Local UI state (mock UX; no backend wiring yet)
    let query = "";

    const formatIso = (iso?: string | null) => {
        if (!iso) return null;
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) return iso;
        return d.toLocaleString();
    };

    const safeNum = (n: number | null | undefined) =>
        typeof n === "number" ? n : 0;

    const filteredThreads = () => {
        const q = query.trim().toLowerCase();
        if (!q) return threads;

        return threads.filter((t) => {
            const hay =
                `${t.title ?? ""}\n${t.excerpt ?? ""}\n${(t.tags ?? []).join(" ")}`.toLowerCase();
            return hay.includes(q);
        });
    };

    const categoryTitle = () => `${category?.name ?? "Category"} • Forums`;

    const threadHref = (threadId: string) =>
        `/forums/t/${encodeURIComponent(threadId)}`;

    const categoryHref = (slug: string) =>
        `/forums/c/${encodeURIComponent(slug)}`;

    const canCreateThread = () => {
        // UX gating only; server must enforce auth + tenant scoping + permissions.
        return !!user?.id && !!tenant_schema && !(category?.is_locked ?? false);
    };

    const newThreadHref = () => {
        const cid = category?.id ?? "";
        return cid
            ? `/forums/new?category_id=${encodeURIComponent(cid)}`
            : "/forums/new";
    };
</script>

<svelte:head>
    <title>{categoryTitle()}</title>
</svelte:head>

<AppShell
    title={category?.name ?? title}
    subtitle={category?.description ?? subtitle}
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
            href="/forums"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
            title="Forums home (placeholder route)"
        >
            Forums
        </a>
    </svelte:fragment>

    <!-- Phase note / mocked UI callout -->
    <section class="rounded-2xl border border-border bg-muted/20 p-5 sm:p-6">
        <div
            class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"
        >
            <div class="min-w-0">
                <div class="text-sm font-medium">Forums UI scaffold (mock)</div>
                <p class="mt-1 text-sm text-muted-foreground">
                    This page is intentionally backend-light. It locks down the
                    UX/UI structure so Phase 6 can plug in real Ash resources,
                    signals, directives, and agent participation.
                </p>
            </div>

            <div class="flex items-center gap-2">
                <a
                    use:inertia
                    href={canCreateThread() ? newThreadHref() : "/forums"}
                    class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                         bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3 ${
                             canCreateThread()
                                 ? ""
                                 : "opacity-60 pointer-events-none"
                         }`}
                    aria-disabled={!canCreateThread()}
                    title={canCreateThread()
                        ? "Create a new thread"
                        : !user?.id
                          ? "Sign in to create threads."
                          : !tenant_schema
                            ? "Select an org/tenant to create threads."
                            : category?.is_locked
                              ? "This category is locked."
                              : "Cannot create thread."}
                >
                    New thread
                </a>
                <a
                    href="/admin/tenant"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                         border border-border bg-background hover:bg-muted h-9 px-3"
                >
                    Admin
                </a>
            </div>
        </div>
    </section>

    <!-- Breadcrumbs -->
    <nav class="mt-6 text-sm text-muted-foreground">
        <a
            use:inertia
            href="/forums"
            class="hover:text-foreground transition-colors">Forums</a
        >
        <span class="mx-2">/</span>
        <a
            use:inertia
            href={categoryHref(category.slug)}
            class="hover:text-foreground transition-colors"
        >
            {category?.name ?? "Category"}
        </a>
    </nav>

    <!-- Category header / stats -->
    <section class="mt-4 rounded-2xl border border-border bg-card p-5 sm:p-6">
        <div
            class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
        >
            <div class="min-w-0">
                <h2 class="text-lg font-semibold tracking-tight truncate">
                    {category?.name ?? "Category"}
                    {#if category?.is_locked}
                        <span
                            class="ml-2 rounded-full border border-border bg-muted/40 px-2 py-0.5 text-xs text-muted-foreground"
                        >
                            Locked
                        </span>
                    {/if}
                </h2>
                {#if category?.description}
                    <p class="mt-1 text-sm text-muted-foreground">
                        {category.description}
                    </p>
                {/if}
            </div>

            <div class="grid grid-cols-3 gap-3 text-sm">
                <div class="rounded-xl border border-border bg-background p-3">
                    <div class="text-xs text-muted-foreground">Threads</div>
                    <div class="mt-1 font-semibold tabular-nums">
                        {safeNum(category?.stats?.threads)}
                    </div>
                </div>
                <div class="rounded-xl border border-border bg-background p-3">
                    <div class="text-xs text-muted-foreground">Posts</div>
                    <div class="mt-1 font-semibold tabular-nums">
                        {safeNum(category?.stats?.posts)}
                    </div>
                </div>
                <div class="rounded-xl border border-border bg-background p-3">
                    <div class="text-xs text-muted-foreground">
                        Last activity
                    </div>
                    <div class="mt-1 text-xs text-muted-foreground">
                        {formatIso(category?.stats?.last_activity_at) ?? "—"}
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- Search / filters -->
    <section class="mt-6 rounded-2xl border border-border bg-card p-5 sm:p-6">
        <div
            class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
        >
            <div class="min-w-0">
                <div class="text-sm font-medium">Threads</div>
                <div class="mt-1 text-xs text-muted-foreground">
                    Search is client-side for now; Phase 6 will replace with
                    server-side filters.
                </div>
            </div>

            <div class="flex items-center gap-2">
                <input
                    class="h-9 w-full sm:w-80 rounded-md border border-border bg-background px-3 text-sm"
                    placeholder="Search threads…"
                    bind:value={query}
                    aria-label="Search threads"
                />
                <button
                    type="button"
                    class="h-9 rounded-md border border-border bg-background px-3 text-sm font-medium hover:bg-muted transition-colors"
                    on:click={() => (query = "")}
                    disabled={!query.trim()}
                >
                    Clear
                </button>
            </div>
        </div>
    </section>

    <!-- Thread list -->
    <section class="mt-4">
        <div class="grid gap-3">
            {#if filteredThreads().length === 0}
                <div
                    class="rounded-2xl border border-border bg-card p-8 text-center"
                >
                    <div class="text-sm font-medium">No threads found</div>
                    <p class="mt-2 text-sm text-muted-foreground">
                        Try a different search term.
                    </p>
                </div>
            {:else}
                {#each filteredThreads() as t (t.id)}
                    <article
                        class="rounded-2xl border border-border bg-card p-5 sm:p-6 hover:bg-muted/20 transition-colors"
                    >
                        <div
                            class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
                        >
                            <div class="min-w-0">
                                <div class="flex items-center gap-2 flex-wrap">
                                    {#if t.is_pinned}
                                        <span
                                            class="rounded-full border border-border bg-primary/10 px-2 py-0.5 text-xs text-primary"
                                        >
                                            Pinned
                                        </span>
                                    {/if}
                                    {#if t.is_locked}
                                        <span
                                            class="rounded-full border border-border bg-muted/40 px-2 py-0.5 text-xs text-muted-foreground"
                                        >
                                            Locked
                                        </span>
                                    {/if}
                                </div>

                                <h3
                                    class="mt-2 text-base sm:text-lg font-semibold tracking-tight"
                                >
                                    <a
                                        use:inertia
                                        href={threadHref(t.id)}
                                        class="hover:underline underline-offset-4"
                                        title="Thread page (placeholder route)"
                                    >
                                        {t.title}
                                    </a>
                                </h3>

                                {#if t.excerpt}
                                    <p
                                        class="mt-1 text-sm text-muted-foreground"
                                    >
                                        {t.excerpt}
                                    </p>
                                {/if}

                                {#if t.tags && t.tags.length > 0}
                                    <div
                                        class="mt-3 flex flex-wrap items-center gap-2"
                                    >
                                        {#each t.tags as tag (tag)}
                                            <span
                                                class="rounded-full border border-border bg-background px-2 py-0.5 text-xs text-muted-foreground"
                                            >
                                                #{tag}
                                            </span>
                                        {/each}
                                    </div>
                                {/if}

                                <div class="mt-3 text-xs text-muted-foreground">
                                    {#if t.author?.name}
                                        <span
                                            class="font-medium text-foreground"
                                            >{t.author.name}</span
                                        >
                                        <span class="mx-2">•</span>
                                    {/if}
                                    <span
                                        >Updated {formatIso(t.updated_at) ??
                                            "—"}</span
                                    >
                                </div>
                            </div>

                            <div
                                class="shrink-0 grid grid-cols-3 gap-3 text-sm"
                            >
                                <div
                                    class="rounded-xl border border-border bg-background p-3 text-center"
                                >
                                    <div class="text-xs text-muted-foreground">
                                        Replies
                                    </div>
                                    <div
                                        class="mt-1 font-semibold tabular-nums"
                                    >
                                        {safeNum(t.stats?.replies)}
                                    </div>
                                </div>
                                <div
                                    class="rounded-xl border border-border bg-background p-3 text-center"
                                >
                                    <div class="text-xs text-muted-foreground">
                                        Views
                                    </div>
                                    <div
                                        class="mt-1 font-semibold tabular-nums"
                                    >
                                        {safeNum(t.stats?.views)}
                                    </div>
                                </div>
                                <div
                                    class="rounded-xl border border-border bg-background p-3 text-center"
                                >
                                    <div class="text-xs text-muted-foreground">
                                        Reacts
                                    </div>
                                    <div
                                        class="mt-1 font-semibold tabular-nums"
                                    >
                                        {safeNum(t.stats?.reactions)}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </article>
                {/each}
            {/if}
        </div>
    </section>

    <!-- Footer hint -->
    <section
        class="mt-10 rounded-2xl border border-border bg-muted/20 p-5 sm:p-6"
    >
        <div class="text-sm font-medium">Planned (Phase 6)</div>
        <ul class="mt-2 space-y-1 text-sm text-muted-foreground list-disc pl-5">
            <li>
                Category + thread + post resources (Ash), tenant-scoped where
                needed.
            </li>
            <li>
                Agent participation as first-class (with directive-backed
                actions).
            </li>
            <li>Signals + directives audit trail surfaces on every thread.</li>
            <li>Moderation queue + anti-abuse basics.</li>
        </ul>
    </section>
</AppShell>
