<script lang="ts">
    import { inertia } from "@inertiajs/svelte";
    import AppShell from "../lib/components/AppShell.svelte";

    // Shared props (provided globally by the backend via Inertia shared props)
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

    // Page chrome
    export let title: string = "New category";
    export let subtitle: string =
        "Create a forum category for your organization (Phase 2C wiring).";

    type Banner = { kind: "info" | "error" | "success"; message: string };

    // Form state
    let name = "";
    let slug = "";
    let description = "";
    let status: "active" | "archived" = "active";

    let isSubmitting = false;
    let banner: Banner | null = null;

    const trim = (s: string) => (s ?? "").trim();

    const slugify = (s: string) =>
        trim(s)
            .toLowerCase()
            .replace(/['"]/g, "")
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/(^-|-$)/g, "");

    function maybeAutofillSlug() {
        // If the slug is empty, or if it still matches a slugified version of the previous name,
        // keep it in sync.
        if (!trim(slug)) {
            slug = slugify(name);
        }
    }

    const getCsrfToken = () =>
        document
            .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
            ?.getAttribute("content") ?? "";

    const canCreateCategoryClientSide = () => {
        // Phase 2C: this is a UX gate only.
        // Server must enforce tenant scoping + membership/role checks.
        const role = (user?.role ?? "").toString();
        return (
            !!user?.id &&
            !!tenant_schema &&
            (role === "owner" || role === "admin")
        );
    };

    const validationErrors = () => {
        const errs: string[] = [];

        const n = trim(name);
        const s = trim(slug);
        const d = trim(description);

        if (!n) errs.push("Name is required.");
        if (n.length > 64) errs.push("Name must be 64 characters or fewer.");

        if (!s) errs.push("Slug is required.");
        if (s.length > 64) errs.push("Slug must be 64 characters or fewer.");
        if (s && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(s)) {
            errs.push(
                "Slug must be lowercase and contain only letters, numbers, and hyphens.",
            );
        }

        if (d && d.length > 300)
            errs.push("Description must be 300 characters or fewer.");

        if (!tenant_schema)
            errs.push("Tenant context is missing. Select an org/tenant first.");

        return errs;
    };

    const canSubmit = () =>
        canCreateCategoryClientSide() &&
        !isSubmitting &&
        validationErrors().length === 0;

    async function onSubmit(e: Event) {
        e.preventDefault();

        banner = null;

        if (!user?.id) {
            banner = {
                kind: "error",
                message: "You must be signed in to create a category.",
            };
            return;
        }

        const role = (user?.role ?? "").toString();
        if (!(role === "owner" || role === "admin")) {
            banner = {
                kind: "error",
                message: "Only org admins can create categories.",
            };
            return;
        }

        const errs = validationErrors();
        if (errs.length > 0) {
            banner = { kind: "error", message: errs[0] };
            return;
        }

        isSubmitting = true;

        try {
            const csrf = getCsrfToken();

            // Phase 2C wiring target:
            // Backend should implement:
            //   POST /forums/categories
            // Body:
            //   { name, slug, description, status }
            //
            // Expected success responses (any one is fine):
            // - { ok: true, redirect_to: "/forums/c/<slug>", category: {...} }
            // - { ok: true, category: { slug: "..." } }
            // - 204/empty body (fallback redirect)
            const payload = {
                name: trim(name),
                slug: trim(slug),
                description: trim(description) || null,
                status,
            };

            // Keep this log to make backend wiring easy; remove once stabilized.
            console.info("[ForumsCategoryNew] create category payload", {
                ...payload,
                tenant: tenant ?? tenant_schema ?? null,
                organization_id: current_organization?.id ?? null,
            });

            const res = await fetch("/forums/categories", {
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
                        `Failed to create category (${res.status}).`,
                };
                return;
            }

            let redirectTo = "/forums";
            try {
                const data = await res.json().catch(() => null);

                const candidate = (data as any)?.redirect_to;
                const createdSlug = (data as any)?.category?.slug;

                if (typeof candidate === "string" && candidate.trim() !== "") {
                    redirectTo = candidate;
                } else if (
                    typeof createdSlug === "string" &&
                    createdSlug.trim() !== ""
                ) {
                    redirectTo = `/forums/c/${encodeURIComponent(createdSlug)}`;
                }
            } catch {
                // Non-JSON response: just fall back to /forums.
            }

            banner = {
                kind: "success",
                message: "Category created. Redirecting…",
            };

            window.location.href = redirectTo;
        } catch (err: any) {
            banner = {
                kind: "error",
                message: err?.message ?? "Failed to create category.",
            };
        } finally {
            isSubmitting = false;
        }
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
            href="/forums"
            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
             border border-border bg-background hover:bg-muted h-9 px-3"
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

    {#if !tenant_schema}
        <section
            class="mb-6 rounded-2xl border border-primary/30 bg-primary/10 p-5"
        >
            <div class="text-sm font-medium">Tenant context not selected</div>
            <p class="mt-1 text-sm text-muted-foreground">
                Categories are tenant-scoped. Select an org/tenant first, then
                come back here.
                <a
                    href="/admin/tenant"
                    class="ml-1 underline hover:text-foreground transition-colors"
                >
                    Select tenant
                </a>
            </p>
        </section>
    {/if}

    <section class="rounded-2xl border border-border bg-card p-6 sm:p-8">
        <div class="flex flex-col gap-2">
            <h2 class="text-lg font-semibold tracking-tight">
                Category details
            </h2>
            <p class="text-sm text-muted-foreground">
                Create a stable category “home” for threads. Use a short,
                URL-safe slug (e.g. <code>support</code>,
                <code>product-updates</code>).
            </p>
        </div>

        <form class="mt-6 space-y-5" onsubmit={onSubmit}>
            <div class="space-y-2">
                <label class="text-sm font-medium" for="category_name"
                    >Name</label
                >
                <input
                    id="category_name"
                    name="name"
                    type="text"
                    class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                           ring-offset-background placeholder:text-muted-foreground
                           focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                    placeholder="Support"
                    bind:value={name}
                    oninput={maybeAutofillSlug}
                    disabled={isSubmitting}
                    required
                />
                <div class="text-xs text-muted-foreground">
                    Visible label in the UI.
                </div>
            </div>

            <div class="space-y-2">
                <label class="text-sm font-medium" for="category_slug"
                    >Slug</label
                >
                <input
                    id="category_slug"
                    name="slug"
                    type="text"
                    class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                           ring-offset-background placeholder:text-muted-foreground
                           focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                    placeholder="support"
                    bind:value={slug}
                    disabled={isSubmitting}
                    required
                />
                <div class="text-xs text-muted-foreground">
                    Used in URLs: <code>/forums/c/&lt;slug&gt;</code>. Lowercase
                    letters, numbers, and hyphens only.
                </div>
            </div>

            <div class="space-y-2">
                <label class="text-sm font-medium" for="category_description"
                    >Description</label
                >
                <textarea
                    id="category_description"
                    name="description"
                    class="min-h-[96px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                           ring-offset-background placeholder:text-muted-foreground
                           focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                    placeholder="Help, troubleshooting, and how-to questions."
                    bind:value={description}
                    disabled={isSubmitting}
                ></textarea>
                <div class="text-xs text-muted-foreground">
                    Optional. Shown under the category title.
                </div>
            </div>

            <div class="space-y-2">
                <label class="text-sm font-medium" for="category_status"
                    >Status</label
                >
                <select
                    id="category_status"
                    name="status"
                    class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                           focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                    bind:value={status}
                    disabled={isSubmitting}
                >
                    <option value="active">Active</option>
                    <option value="archived">Archived</option>
                </select>
                <div class="text-xs text-muted-foreground">
                    Archived categories remain visible but should not receive
                    new threads (enforced server-side).
                </div>
            </div>

            {#if validationErrors().length > 0}
                <div class="rounded-xl border border-border bg-muted/20 p-4">
                    <div class="text-sm font-medium">Needs attention</div>
                    <ul
                        class="mt-2 list-disc pl-5 text-sm text-muted-foreground space-y-1"
                    >
                        {#each validationErrors() as err (err)}
                            <li>{err}</li>
                        {/each}
                    </ul>
                </div>
            {/if}

            <div
                class="flex flex-col-reverse sm:flex-row sm:items-center sm:justify-between gap-3 pt-2"
            >
                <a
                    use:inertia
                    href="/forums"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                           border border-border bg-background hover:bg-muted h-10 px-4"
                >
                    Cancel
                </a>

                <button
                    type="submit"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                           bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4
                           disabled:opacity-60 disabled:pointer-events-none"
                    disabled={!canSubmit()}
                    title={!canCreateCategoryClientSide()
                        ? "Sign in and select a tenant first."
                        : validationErrors().length > 0
                          ? validationErrors()[0]
                          : "Create category"}
                >
                    {#if isSubmitting}
                        Creating…
                    {:else}
                        Create category
                    {/if}
                </button>
            </div>
        </form>
    </section>

    <section class="mt-6 rounded-2xl border border-border bg-muted/20 p-5">
        <div class="text-sm font-medium">Phase 2C note</div>
        <p class="mt-1 text-sm text-muted-foreground">
            This page is intended to be backed by tenant-scoped Ash resources.
            On success, the backend should emit <code
                >forum.category.created</code
            > as a Signal and keep the write path auditable.
        </p>
    </section>
</AppShell>
