<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    type UserSummary = {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    };

    type OrgOption = {
        id: string;
        name?: string | null;
        slug?: string | null;
        tier?: string | null;
    };

    type Thread = {
        id: string;
        title: string;
        category?: string | null;
        status?: "open" | "closed" | "archived" | string | null;
        created_at?: string | null;
        updated_at?: string | null;
        author?: {
            id?: string | null;
            name?: string | null;
            handle?: string | null;
            avatar_url?: string | null;
            kind?: "human" | "agent" | string | null;
        } | null;
        tags?: string[] | null;
    };

    type Post = {
        id: string;
        role?: "human" | "agent" | "system" | string | null;
        author?: {
            id?: string | null;
            name?: string | null;
            handle?: string | null;
            avatar_url?: string | null;
            kind?: "human" | "agent" | string | null;
        } | null;
        created_at?: string | null;
        body: string;
        reactions?: Record<string, number> | null;
    };

    // Page chrome
    export let title: string = "Forums";
    export let subtitle: string =
        "Preview UI for an agent-native forum (mocked).";

    // Shared Inertia props (provided globally by the backend via shared props)
    export let user: UserSummary | null = null;
    export let tenant: string | null = null;
    export let tenant_schema: string | null = null;
    export let organizations: OrgOption[] | null = null;
    export let current_organization: OrgOption | null = null;

    // Forums props (mocked for now; will be replaced by Phase 6 resources)
    export let thread: Thread | null = null;
    export let posts: Post[] | null = null;

    // Capability flags (foundation for later)
    export let can_reply: boolean = false;
    export let can_moderate: boolean = false;

    const nowIso = () => new Date().toISOString();

    const fallbackThread: Thread = {
        id: "thread_demo_001",
        title: "How should agents participate in threads without causing side effects?",
        category: "Product / Agent-native",
        status: "open",
        created_at: new Date(Date.now() - 1000 * 60 * 60 * 18).toISOString(),
        updated_at: new Date(Date.now() - 1000 * 60 * 25).toISOString(),
        author: {
            id: "user_demo_001",
            name: "Travis",
            handle: "travis",
            kind: "human",
            avatar_url: null,
        },
        tags: ["signals", "directives", "moderation"],
    };

    const fallbackPosts: Post[] = [
        {
            id: "post_demo_001",
            role: "human",
            author: {
                id: "user_demo_001",
                name: "Travis",
                handle: "travis",
                kind: "human",
                avatar_url: null,
            },
            created_at: new Date(
                Date.now() - 1000 * 60 * 60 * 18,
            ).toISOString(),
            body: "I want the forum to feel *agent-native* — agents can draft replies, summarize threads, and propose actions.\n\nBut they must not cause side effects unless backed by **Directives**. What should the UX look like so this is obvious to humans?",
            reactions: { "👍": 3, "💡": 1 },
        },
        {
            id: "post_demo_002",
            role: "agent",
            author: {
                id: "agent_demo_mod_001",
                name: "ModBot",
                handle: "modbot",
                kind: "agent",
                avatar_url: null,
            },
            created_at: new Date(Date.now() - 1000 * 60 * 35).toISOString(),
            body: "Proposed UX pattern:\n\n1) Agents can post as **“suggestions”** by default (visually distinct).\n2) Any action (close thread, flag, notify) becomes a **Directive draft** that requires a human click to approve.\n3) Thread timeline shows an audit rail: Signals emitted + Directives requested/approved.\n\nThis keeps the forum readable while still making automation powerful and safe.",
            reactions: { "👍": 5, "✅": 2 },
        },
    ];

    const effectiveThread = () => thread ?? fallbackThread;
    const effectivePosts = () => posts ?? fallbackPosts;

    const isMock = () => !thread || !posts;

    const formatDateTime = (iso: string | null | undefined) => {
        if (!iso) return "—";
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) return iso;
        return d.toLocaleString(undefined, {
            year: "numeric",
            month: "short",
            day: "2-digit",
            hour: "2-digit",
            minute: "2-digit",
        });
    };

    const authorLabel = (
        a: Thread["author"] | Post["author"] | null | undefined,
    ) => {
        if (!a) return "Unknown";
        const name = (a.name ?? "").trim();
        if (name) return name;
        const handle = (a.handle ?? "").trim();
        if (handle) return `@${handle}`;
        return "Unknown";
    };

    const authorBadge = (
        a: Thread["author"] | Post["author"] | null | undefined,
    ) => {
        const kind = (a?.kind ?? "").toString();
        if (kind === "agent") return "Agent";
        if (kind === "human") return "Human";
        return kind ? kind : null;
    };

    const threadStatusClass = (status: string | null | undefined) => {
        const s = (status ?? "").toLowerCase();
        if (s === "open")
            return "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300";
        if (s === "closed")
            return "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300";
        if (s === "archived")
            return "border-slate-500/30 bg-slate-500/10 text-slate-700 dark:text-slate-300";
        return "border-border bg-muted/30 text-muted-foreground";
    };
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

    <!-- Breadcrumbs -->
    <nav class="mb-4 text-sm text-muted-foreground">
        <a use:inertia href="/forums" class="hover:text-foreground"> Forums </a>
        <span class="mx-2">/</span>
        <span class="text-foreground">{effectiveThread().title}</span>
    </nav>

    <!-- Mock mode notice -->
    {#if isMock()}
        <section
            class="mb-6 rounded-2xl border border-primary/30 bg-primary/10 px-4 py-4 sm:px-6"
        >
            <div
                class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
            >
                <div class="min-w-0">
                    <div class="font-medium">Forums UI foundation (mocked)</div>
                    <div class="mt-1 text-sm text-muted-foreground">
                        This page is intentionally backend-agnostic for now.
                        Phase 6 will wire threads/posts to Ash resources and
                        emit Signals + Directives for agent interactions.
                    </div>
                </div>
                <div class="flex items-center gap-2">
                    <a
                        use:inertia
                        href="/forums"
                        class="inline-flex items-center justify-center rounded-md text-xs font-medium transition-colors
                         border border-border bg-background hover:bg-muted h-8 px-3"
                    >
                        Back to list
                    </a>
                    <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md text-xs font-medium transition-colors
                         bg-primary text-primary-foreground hover:bg-primary/90 h-8 px-3 disabled:opacity-60 disabled:pointer-events-none"
                        disabled={true}
                        title="Reply will be enabled when Phase 6 APIs exist."
                    >
                        Reply (coming soon)
                    </button>
                </div>
            </div>
        </section>
    {/if}

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <!-- Main thread + posts -->
        <section class="lg:col-span-8 space-y-4">
            <!-- Thread header -->
            <div
                class="rounded-2xl border border-border bg-card text-card-foreground p-6"
            >
                <div class="flex flex-col gap-3">
                    <div class="flex flex-wrap items-center gap-2">
                        {#if effectiveThread().category}
                            <span
                                class="inline-flex items-center rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                            >
                                {effectiveThread().category}
                            </span>
                        {/if}

                        <span
                            class={`inline-flex items-center rounded-full border px-3 py-1 text-xs ${threadStatusClass(
                                effectiveThread().status,
                            )}`}
                        >
                            {(effectiveThread().status ?? "status").toString()}
                        </span>

                        {#if (effectiveThread().tags ?? []).length > 0}
                            <div class="flex flex-wrap items-center gap-2">
                                {#each effectiveThread().tags ?? [] as tag (tag)}
                                    <span
                                        class="inline-flex items-center rounded-full border border-border bg-background px-3 py-1 text-xs text-muted-foreground"
                                    >
                                        #{tag}
                                    </span>
                                {/each}
                            </div>
                        {/if}
                    </div>

                    <h2 class="text-2xl font-semibold tracking-tight">
                        {effectiveThread().title}
                    </h2>

                    <div
                        class="flex flex-wrap items-center gap-2 text-sm text-muted-foreground"
                    >
                        <span class="inline-flex items-center gap-2">
                            <span class="font-medium text-foreground">
                                {authorLabel(effectiveThread().author)}
                            </span>
                            {#if authorBadge(effectiveThread().author)}
                                <span
                                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px]"
                                    title="Author type"
                                >
                                    {authorBadge(effectiveThread().author)}
                                </span>
                            {/if}
                        </span>
                        <span>•</span>
                        <span title="Created">
                            {formatDateTime(effectiveThread().created_at)}
                        </span>
                        <span>•</span>
                        <span title="Last updated">
                            Updated {formatDateTime(
                                effectiveThread().updated_at,
                            )}
                        </span>
                    </div>
                </div>
            </div>

            <!-- Posts -->
            <div class="space-y-4">
                {#each effectivePosts() as post (post.id)}
                    <article
                        class="rounded-2xl border border-border bg-card text-card-foreground p-6"
                    >
                        <header class="flex items-start justify-between gap-4">
                            <div class="min-w-0">
                                <div class="flex flex-wrap items-center gap-2">
                                    <span class="font-semibold truncate">
                                        {authorLabel(post.author)}
                                    </span>

                                    {#if authorBadge(post.author)}
                                        <span
                                            class="inline-flex items-center rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[11px] text-muted-foreground"
                                            title="Poster type"
                                        >
                                            {authorBadge(post.author)}
                                        </span>
                                    {/if}

                                    {#if post.role}
                                        <span
                                            class="inline-flex items-center rounded-full border border-border bg-background px-2 py-0.5 text-[11px] text-muted-foreground"
                                            title="Post role"
                                        >
                                            {post.role}
                                        </span>
                                    {/if}
                                </div>

                                <div class="mt-1 text-xs text-muted-foreground">
                                    {formatDateTime(post.created_at)}
                                </div>
                            </div>

                            <div class="flex items-center gap-2">
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center rounded-md text-xs font-medium transition-colors
                                     border border-border bg-background hover:bg-muted h-8 px-3 disabled:opacity-60 disabled:pointer-events-none"
                                    disabled={true}
                                    title="Reactions will be wired later."
                                >
                                    React
                                </button>
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center rounded-md text-xs font-medium transition-colors
                                     border border-border bg-background hover:bg-muted h-8 px-3 disabled:opacity-60 disabled:pointer-events-none"
                                    disabled={true}
                                    title="Permalinks will be wired later."
                                >
                                    Link
                                </button>
                            </div>
                        </header>

                        <div
                            class="mt-4 whitespace-pre-wrap leading-relaxed text-sm"
                        >
                            {post.body}
                        </div>

                        {#if post.reactions && Object.keys(post.reactions).length > 0}
                            <div class="mt-4 flex flex-wrap items-center gap-2">
                                {#each Object.entries(post.reactions) as [emoji, count] (emoji)}
                                    <span
                                        class="inline-flex items-center gap-1 rounded-full border border-border bg-muted/30 px-3 py-1 text-xs text-muted-foreground"
                                        title="Mocked reaction counts"
                                    >
                                        <span class="text-foreground"
                                            >{emoji}</span
                                        >
                                        <span>{count}</span>
                                    </span>
                                {/each}
                            </div>
                        {/if}
                    </article>
                {/each}
            </div>

            <!-- Reply composer (disabled for now) -->
            <div
                class="rounded-2xl border border-border bg-card text-card-foreground p-6"
            >
                <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0">
                        <div class="font-semibold">Reply</div>
                        <p class="mt-1 text-sm text-muted-foreground">
                            Replies will be enabled when forum resources and
                            permissions are implemented.
                        </p>
                    </div>

                    <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                         bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-4 disabled:opacity-60 disabled:pointer-events-none"
                        disabled={!can_reply}
                        title={can_reply
                            ? "Post reply"
                            : "Reply is not enabled yet."}
                    >
                        Post reply
                    </button>
                </div>

                <div class="mt-4">
                    <textarea
                        class="w-full rounded-md border border-border bg-background px-3 py-2 text-sm disabled:opacity-60"
                        rows={5}
                        placeholder="Write a reply…"
                        disabled={!can_reply}
                    ></textarea>
                    <div class="mt-2 text-xs text-muted-foreground">
                        Drafted agent replies will appear as suggestions in
                        Phase 6 (no side effects without directives).
                    </div>
                </div>
            </div>
        </section>

        <!-- Sidebar -->
        <aside class="lg:col-span-4 space-y-4">
            <!-- Thread actions -->
            <div
                class="rounded-2xl border border-border bg-card text-card-foreground p-6"
            >
                <div class="font-semibold">Thread actions</div>
                <div class="mt-4 grid grid-cols-1 gap-2">
                    <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                         bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-4 disabled:opacity-60 disabled:pointer-events-none"
                        disabled={!can_reply}
                        title="Reply will be enabled later."
                    >
                        Reply
                    </button>

                    <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                         border border-border bg-background hover:bg-muted h-9 px-4 disabled:opacity-60 disabled:pointer-events-none"
                        disabled={true}
                        title="Subscriptions will be implemented later."
                    >
                        Subscribe (coming soon)
                    </button>

                    <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                         border border-border bg-background hover:bg-muted h-9 px-4 disabled:opacity-60 disabled:pointer-events-none"
                        disabled={!can_moderate}
                        title="Moderation requires permissions and directive-backed actions."
                    >
                        Moderate
                    </button>
                </div>
            </div>

            <!-- Agent-native UX note -->
            <div class="rounded-2xl border border-border bg-muted/20 p-6">
                <div class="font-semibold">Agent-native principles</div>
                <ul class="mt-3 space-y-2 text-sm text-muted-foreground">
                    <li>
                        • Agents can participate, but any side effect is gated
                        by Directives.
                    </li>
                    <li>
                        • Thread timeline will show Signals + Directives for
                        auditability.
                    </li>
                    <li>• Escalation to humans is a first-class path.</li>
                </ul>
            </div>

            <!-- Debug-ish metadata -->
            <div
                class="rounded-2xl border border-border bg-card text-card-foreground p-6"
            >
                <div class="font-semibold">Context</div>
                <div class="mt-3 space-y-2 text-sm">
                    <div class="flex items-center justify-between gap-3">
                        <span class="text-muted-foreground">Tenant</span>
                        <span class="font-medium">
                            {tenant ?? tenant_schema ?? "—"}
                        </span>
                    </div>
                    <div class="flex items-center justify-between gap-3">
                        <span class="text-muted-foreground">Thread ID</span>
                        <span class="font-mono text-xs"
                            >{effectiveThread().id}</span
                        >
                    </div>
                    <div class="flex items-center justify-between gap-3">
                        <span class="text-muted-foreground">Rendered</span>
                        <span class="font-mono text-xs">{nowIso()}</span>
                    </div>
                </div>
            </div>
        </aside>
    </div>
</AppShell>
