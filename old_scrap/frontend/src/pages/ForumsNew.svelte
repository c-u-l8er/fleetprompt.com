<svelte:options runes={true} />

<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    type UserProp = {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    };

    type OrgProp = {
        id: string;
        name: string;
        slug: string;
    };

    type Category = {
        id: string;
        slug: string;
        name: string;
        description?: string;
    };

    const fallbackCategories: Category[] = [
        {
            id: "cat_getting_started",
            slug: "getting-started",
            name: "Getting started",
            description: "Announcements, onboarding, and FAQs.",
        },
        {
            id: "cat_packages",
            slug: "packages",
            name: "Packages",
            description: "Marketplace packages, installs, and troubleshooting.",
        },
        {
            id: "cat_agents",
            slug: "agents",
            name: "Agents",
            description: "Agent prompts, behavior, and operations.",
        },
        {
            id: "cat_signals",
            slug: "signals",
            name: "Signals & directives",
            description:
                "Operational truth, audit trails, and side-effect control.",
        },
    ];

    let {
        user = null,
        tenant = null,
        tenant_schema = null,
        organizations = null,
        current_organization = null,
        title = "New thread",
        subtitle = "Start a discussion (Phase 2C lighthouse).",
        categories = fallbackCategories,
    } = $props<{
        user?: UserProp | null;
        tenant?: string | null;
        tenant_schema?: string | null;
        organizations?: OrgProp[] | null;
        current_organization?: OrgProp | null;
        title?: string;
        subtitle?: string;
        categories?: Category[];
    }>();

    // Form state
    type ThreadType = "discussion" | "question" | "showcase";
    const threadTypes: Array<{
        value: ThreadType;
        label: string;
        hint: string;
    }> = [
        {
            value: "discussion",
            label: "Discussion",
            hint: "Open-ended thread to explore ideas with the community.",
        },
        {
            value: "question",
            label: "Question",
            hint: "Get help — include context, expected outcome, and logs if applicable.",
        },
        {
            value: "showcase",
            label: "Showcase",
            hint: "Share an agent, package, workflow, or integration outcome.",
        },
    ];

    let categoryId = $state("");
    let threadType = $state<ThreadType>("discussion");

    // Initialize category selection (runes-safe):
    // - Prefer `?category_id=...` if it matches a provided category
    // - Otherwise default to the first category
    // - If categories change and the current selection becomes invalid, fall back to the first category
    let didInitCategoryId = $state(false);

    $effect(() => {
        const cats = Array.isArray(categories) ? categories : [];
        if (cats.length === 0) return;

        // One-time init: respect URL preselect if valid.
        if (!didInitCategoryId) {
            let preselected: string | null = null;

            try {
                preselected = new URLSearchParams(window.location.search).get(
                    "category_id",
                );
            } catch {
                preselected = null;
            }

            const validPreselected =
                !!preselected && cats.some((c) => c.id === preselected)
                    ? preselected
                    : null;

            categoryId = validPreselected ?? cats[0]!.id;
            didInitCategoryId = true;
            return;
        }

        // Keep selection valid if categories update.
        if (!cats.some((c) => c.id === categoryId)) {
            categoryId = cats[0]!.id;
        }
    });

    let subject = $state("");
    let body = $state("");
    let tags = $state(""); // comma-separated for now
    let subscribeToReplies = $state(true);
    let allowAgentAssist = $state(true);

    let isSubmitting = $state(false);
    let mode = $state<"edit" | "preview">("edit");
    let banner = $state<{
        kind: "info" | "error" | "success";
        message: string;
    } | null>(null);

    // Debug helper: append ?fp_debug=1 to the URL to show live form state.
    let showDebug = $state(false);
    try {
        showDebug = new URLSearchParams(window.location.search).has("fp_debug");
    } catch {
        showDebug = false;
    }

    const trim = (s: string) => (s ?? "").trim();

    const getCsrfToken = () =>
        document
            .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
            ?.getAttribute("content") ?? "";

    const selectedCategory = () =>
        categories.find((c) => c.id === categoryId) ?? null;

    const parsedTags = () =>
        trim(tags)
            .split(",")
            .map((t) => trim(t))
            .filter(Boolean)
            .slice(0, 8);

    const validationErrors = $derived.by(() => {
        const errs: string[] = [];

        if (!trim(subject)) errs.push("Title is required.");
        if (trim(subject).length > 120)
            errs.push("Title must be 120 characters or fewer.");
        if (!trim(body)) errs.push("Body is required.");
        if (trim(body).length < 20)
            errs.push("Body should be at least 20 characters (add context).");
        if (!categoryId) errs.push("Category is required.");

        return errs;
    });

    const categoriesReady = $derived.by(() => {
        return Array.isArray(categories) && categories.length > 0;
    });

    const canSubmit = $derived.by(() => {
        // Require a signed-in user, a selected tenant, and real categories (Phase 2C tenant-scoped writes)
        if (!user?.id) return false;
        if (!tenant_schema) return false;
        if (!categoriesReady) return false;

        return !isSubmitting && validationErrors.length === 0;
    });

    async function onSubmit(e: Event) {
        e.preventDefault();

        banner = null;

        if (!user?.id) {
            banner = {
                kind: "error",
                message: "You must be signed in to create a thread.",
            };
            return;
        }

        if (!tenant_schema) {
            banner = {
                kind: "error",
                message:
                    "Tenant context is missing. Select an org/tenant first.",
            };
            return;
        }

        if (validationErrors.length > 0) {
            banner = { kind: "error", message: validationErrors[0] };
            return;
        }

        isSubmitting = true;
        try {
            const csrf = getCsrfToken();

            const payload = {
                category_id: categoryId,
                title: trim(subject),
                body: trim(body),
            };

            console.info("[ForumsNew] create thread payload", {
                ...payload,
                thread_type: threadType,
                tags: parsedTags(),
                preferences: {
                    subscribe_to_replies: !!subscribeToReplies,
                    allow_agent_assist: !!allowAgentAssist,
                },
                tenant: tenant ?? tenant_schema ?? null,
                organization_id: current_organization?.id ?? null,
            });

            const res = await fetch("/forums/threads", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify(payload),
            });

            if (!res.ok) {
                const text = await res.text().catch(() => "");
                banner = {
                    kind: "error",
                    message:
                        text?.trim() ||
                        `Failed to create thread (${res.status}).`,
                };
                return;
            }

            let redirectTo: string | null = null;
            try {
                const data = await res.json().catch(() => null);
                const candidate = (data as any)?.redirect_to;
                const threadId = (data as any)?.thread?.id;

                if (typeof candidate === "string" && candidate.trim() !== "") {
                    redirectTo = candidate;
                } else if (
                    typeof threadId === "string" &&
                    threadId.trim() !== ""
                ) {
                    redirectTo = `/forums/t/${encodeURIComponent(threadId)}`;
                }
            } catch {
                // Non-JSON response: fall back below.
            }

            banner = {
                kind: "success",
                message: "Thread created. Redirecting…",
            };

            window.location.href = redirectTo ?? "/forums";
        } catch (err: any) {
            banner = {
                kind: "error",
                message: err?.message ?? "Failed to create thread.",
            };
        } finally {
            isSubmitting = false;
        }
    }
</script>

<svelte:head>
    <title>New thread • FleetPrompt</title>
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

        <!-- Placeholder route; will be added when forums land -->
        <a
            use:inertia
            href="/forums"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
            title="Back to forums (route will be added later)"
        >
            Forums
        </a>
    </svelte:fragment>

    {#if banner}
        <div
            class={`mb-6 rounded-xl border p-4 ${
                banner.kind === "error"
                    ? "border-destructive/40 bg-destructive/10 text-foreground"
                    : banner.kind === "success"
                      ? "border-primary/30 bg-primary/10 text-foreground"
                      : "border-border bg-muted/30 text-foreground"
            }`}
            role={banner.kind === "error" ? "alert" : "status"}
        >
            <div class="text-sm font-medium">{banner.message}</div>
        </div>
    {/if}

    {#if !user}
        <div class="rounded-2xl border border-border bg-card p-6">
            <div class="text-sm text-muted-foreground">
                You’re not signed in. Creating threads requires authentication.
            </div>
            <div class="mt-4 flex gap-2">
                <a
                    use:inertia
                    href="/login"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
                    >Sign in</a
                >
                <a
                    use:inertia
                    href="/register"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 border border-border bg-background hover:bg-muted h-9 px-3"
                    >Create account</a
                >
            </div>
        </div>
    {/if}

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <section class="lg:col-span-8">
            <form
                class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8"
                onsubmit={onSubmit}
            >
                <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                        <h2 class="text-xl font-semibold tracking-tight">
                            Compose
                        </h2>
                        <p class="mt-1 text-sm text-muted-foreground">
                            Keep it crisp. Include context, expected behavior,
                            and what you tried.
                        </p>
                    </div>

                    <div class="flex items-center gap-2">
                        <button
                            type="button"
                            class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                border h-9 px-3 ${
                                    mode === "edit"
                                        ? "border-primary/40 bg-primary/10 text-foreground"
                                        : "border-border bg-background hover:bg-muted"
                                }`}
                            onclick={() => (mode = "edit")}
                        >
                            Edit
                        </button>
                        <button
                            type="button"
                            class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                border h-9 px-3 ${
                                    mode === "preview"
                                        ? "border-primary/40 bg-primary/10 text-foreground"
                                        : "border-border bg-background hover:bg-muted"
                                }`}
                            onclick={() => (mode = "preview")}
                        >
                            Preview
                        </button>
                    </div>
                </div>

                <div class="mt-6 grid grid-cols-1 sm:grid-cols-12 gap-4">
                    <div class="sm:col-span-6">
                        <label for="category" class="block text-sm font-medium"
                            >Category</label
                        >
                        <select
                            id="category"
                            class="mt-1 w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                            bind:value={categoryId}
                        >
                            {#each categories as c (c.id)}
                                <option value={c.id}>{c.name}</option>
                            {/each}
                        </select>
                        {#if selectedCategory()?.description}
                            <div class="mt-1 text-xs text-muted-foreground">
                                {selectedCategory()?.description}
                            </div>
                        {/if}
                    </div>

                    <div class="sm:col-span-6">
                        <label
                            for="threadType"
                            class="block text-sm font-medium">Thread type</label
                        >
                        <select
                            id="threadType"
                            class="mt-1 w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                            bind:value={threadType}
                        >
                            {#each threadTypes as t (t.value)}
                                <option value={t.value}>{t.label}</option>
                            {/each}
                        </select>
                        <div class="mt-1 text-xs text-muted-foreground">
                            {threadTypes.find((t) => t.value === threadType)
                                ?.hint ?? ""}
                        </div>
                    </div>

                    <div class="sm:col-span-12">
                        <label for="subject" class="block text-sm font-medium"
                            >Title</label
                        >
                        <input
                            id="subject"
                            class="mt-1 w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                            placeholder="e.g. How do I make my package install idempotent?"
                            bind:value={subject}
                            maxlength={140}
                        />
                        <div class="mt-1 flex items-center justify-between">
                            <div class="text-xs text-muted-foreground">
                                Aim for clarity. Keep it searchable.
                            </div>
                            <div
                                class="text-xs text-muted-foreground tabular-nums"
                            >
                                {trim(subject).length}/120
                            </div>
                        </div>
                    </div>

                    <div class="sm:col-span-12">
                        <label for="body" class="block text-sm font-medium"
                            >Body</label
                        >

                        {#if mode === "edit"}
                            <textarea
                                id="body"
                                class="mt-1 min-h-[220px] w-full rounded-md border border-border bg-background px-3 py-2 text-sm leading-relaxed"
                                placeholder="Write your post… (Markdown supported later)"
                                bind:value={body}
                            ></textarea>
                            <div class="mt-1 text-xs text-muted-foreground">
                                Mocked for now. When implemented, this will
                                support Markdown + safe rendering.
                            </div>
                        {:else}
                            <div
                                class="mt-1 rounded-md border border-border bg-muted/20 p-4"
                            >
                                {#if trim(body)}
                                    <div class="whitespace-pre-wrap text-sm">
                                        {trim(body)}
                                    </div>
                                {:else}
                                    <div class="text-sm text-muted-foreground">
                                        Nothing to preview yet.
                                    </div>
                                {/if}
                            </div>
                        {/if}
                    </div>

                    <div class="sm:col-span-12">
                        <label for="tags" class="block text-sm font-medium"
                            >Tags</label
                        >
                        <input
                            id="tags"
                            class="mt-1 w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
                            placeholder="comma-separated, e.g. signals, directives, marketplace"
                            bind:value={tags}
                        />
                        <div class="mt-2 flex flex-wrap gap-2">
                            {#each parsedTags() as t (t)}
                                <span
                                    class="inline-flex items-center rounded-full border border-border bg-muted/30 px-2.5 py-1 text-xs text-muted-foreground"
                                    >{t}</span
                                >
                            {/each}
                        </div>
                    </div>

                    <div class="sm:col-span-12">
                        <div class="flex flex-col gap-2">
                            <label class="inline-flex items-center gap-2">
                                <input
                                    type="checkbox"
                                    class="h-4 w-4"
                                    bind:checked={subscribeToReplies}
                                />
                                <span class="text-sm">Subscribe to replies</span
                                >
                            </label>

                            <label class="inline-flex items-center gap-2">
                                <input
                                    type="checkbox"
                                    class="h-4 w-4"
                                    bind:checked={allowAgentAssist}
                                />
                                <span class="text-sm"
                                    >Allow agent assistance (drafts/summaries
                                    later)</span
                                >
                            </label>
                        </div>

                        <div class="mt-2 text-xs text-muted-foreground">
                            Agent actions will be directive-backed; agents
                            should never cause side effects directly.
                        </div>
                    </div>

                    <div class="sm:col-span-12">
                        {#if validationErrors.length > 0}
                            <div
                                class="mb-3 rounded-xl border border-border bg-muted/20 p-4"
                            >
                                <div class="text-sm font-medium">
                                    Needs attention
                                </div>
                                <ul
                                    class="mt-2 list-disc pl-5 text-sm text-muted-foreground space-y-1"
                                >
                                    {#each validationErrors as err (err)}
                                        <li>{err}</li>
                                    {/each}
                                </ul>
                            </div>
                        {/if}

                        {#if showDebug}
                            <div
                                class="mb-3 rounded-xl border border-border bg-muted/10 p-4"
                            >
                                <div class="text-sm font-medium">
                                    Debug (fp_debug)
                                </div>
                                <div
                                    class="mt-2 text-xs text-muted-foreground space-y-1"
                                >
                                    <div>
                                        tenant_schema = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(
                                                tenant_schema,
                                            )}</span
                                        >
                                    </div>
                                    <div>
                                        categoriesReady = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(
                                                categoriesReady,
                                            )}</span
                                        >
                                    </div>
                                    <div>
                                        categoryId = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(categoryId)}</span
                                        >
                                    </div>
                                    <div>
                                        subject = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(subject)}</span
                                        >
                                    </div>
                                    <div>
                                        body.len = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(
                                                trim(body).length,
                                            )}</span
                                        >
                                    </div>
                                    <div>
                                        validationErrors = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(
                                                validationErrors,
                                            )}</span
                                        >
                                    </div>
                                    <div>
                                        canSubmit = <span
                                            class="font-mono text-foreground"
                                            >{JSON.stringify(canSubmit)}</span
                                        >
                                    </div>
                                </div>
                            </div>
                        {/if}

                        <div
                            class="flex flex-col sm:flex-row gap-3 sm:items-center sm:justify-between"
                        >
                            <div class="text-xs text-muted-foreground">
                                {#if tenant}
                                    Posting in tenant:
                                    <code class="rounded bg-muted px-1.5 py-0.5"
                                        >{tenant}</code
                                    >
                                {:else if tenant_schema}
                                    Posting in tenant schema:
                                    <code class="rounded bg-muted px-1.5 py-0.5"
                                        >{tenant_schema}</code
                                    >
                                {:else}
                                    No tenant selected — when forums become
                                    tenant-scoped, you’ll need an org selected.
                                {/if}
                            </div>

                            <button
                                type="submit"
                                class={`inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                                    h-10 px-4 ${
                                        canSubmit
                                            ? "bg-primary text-primary-foreground hover:bg-primary/90"
                                            : "bg-muted text-muted-foreground cursor-not-allowed"
                                    }`}
                                disabled={!canSubmit}
                                title={!user?.id
                                    ? "Sign in to create a thread"
                                    : !tenant_schema
                                      ? "Select an org/tenant first"
                                      : !categoriesReady
                                        ? "No categories are available for this tenant"
                                        : validationErrors.length > 0
                                          ? validationErrors[0]
                                          : "Create thread"}
                            >
                                {#if isSubmitting}
                                    Creating…
                                {:else}
                                    Create thread
                                {/if}
                            </button>
                        </div>
                    </div>
                </div>
            </form>
        </section>

        <aside class="lg:col-span-4 space-y-6">
            <div class="rounded-2xl border border-border bg-card p-6">
                <h3 class="text-sm font-semibold tracking-tight">
                    Posting guidelines
                </h3>
                <ul class="mt-3 space-y-2 text-sm text-muted-foreground">
                    <li>
                        <span class="text-foreground font-medium"
                            >Be specific:</span
                        >
                        include environment, tenant context, and exact behavior.
                    </li>
                    <li>
                        <span class="text-foreground font-medium"
                            >Prefer signals:</span
                        >
                        describe what happened (facts), not what you think caused
                        it.
                    </li>
                    <li>
                        <span class="text-foreground font-medium"
                            >No secrets:</span
                        >
                        redact tokens, webhook URLs, and credentials.
                    </li>
                </ul>
            </div>

            <div class="rounded-2xl border border-border bg-muted/20 p-6">
                <h3 class="text-sm font-semibold tracking-tight">
                    What happens next (planned)
                </h3>
                <div class="mt-3 text-sm text-muted-foreground space-y-2">
                    <p>When forums are implemented, creating a thread will:</p>
                    <ol class="list-decimal pl-5 space-y-1">
                        <li>Create a `Forum.Thread` + first `Forum.Post`.</li>
                        <li>
                            Emit signals like <code>forum.thread.created</code
                            >{" "}
                            and <code>forum.post.created</code>.
                        </li>
                        <li>
                            Allow agents to propose responses and moderation via
                            directives (audit-first).
                        </li>
                    </ol>
                </div>
            </div>
        </aside>
    </div>
</AppShell>
