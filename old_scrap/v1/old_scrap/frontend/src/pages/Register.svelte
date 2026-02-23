<script lang="ts">
    import { inertia } from "@inertiajs/svelte";

    export let title: string = "Create your organization";
    export let error: string | null = null;

    // Prefer a server-provided (digested) logo URL when available (e.g. via Inertia props or a meta tag).
    export let logo_with_text_url: string | null = null;

    let orgName = "";
    let orgSlug = "";

    let ownerName = "";
    let email = "";
    let password = "";
    let passwordConfirm = "";

    let isSubmitting = false;

    const getCsrfToken = () =>
        document
            .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
            ?.getAttribute("content") ?? "";

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

    const slugify = (input: string) => {
        const raw = (input ?? "").trim().toLowerCase();

        // Keep consistent with backend slug rules used elsewhere:
        // lowercase alphanumerics + underscores, 1..63 chars, no leading/trailing underscore.
        const cleaned = raw
            .replace(/[^a-z0-9\s_]/g, "")
            .replace(/\s+/g, "_")
            .replace(/_+/g, "_")
            .replace(/^_+/, "")
            .replace(/_+$/, "");

        return cleaned.slice(0, 63);
    };

    $: {
        // Only auto-fill slug if user hasn't typed one yet.
        if (!orgSlug.trim() && orgName.trim()) {
            orgSlug = slugify(orgName);
        }
    }

    const validate = () => {
        const orgNameTrimmed = orgName.trim();
        const orgSlugTrimmed = orgSlug.trim();
        const emailTrimmed = email.trim();

        if (!orgNameTrimmed) return "Organization name is required.";
        if (!orgSlugTrimmed) return "Organization slug is required.";

        // Conservative slug validation to match backend expectations.
        if (!/^[a-z0-9]+(?:_[a-z0-9]+)*$/.test(orgSlugTrimmed)) {
            return "Organization slug must be lowercase letters/numbers, optionally separated by underscores.";
        }

        if (orgSlugTrimmed.length < 1 || orgSlugTrimmed.length > 63) {
            return "Organization slug must be 1–63 characters.";
        }

        if (!ownerName.trim()) return "Your name is required.";
        if (!emailTrimmed) return "Email is required.";

        // Minimal email validation (backend should validate properly too).
        if (!/^\S+@\S+\.\S+$/.test(emailTrimmed)) {
            return "Enter a valid email address.";
        }

        if (!password) return "Password is required.";
        if (password.length < 8)
            return "Password must be at least 8 characters.";
        if (password !== passwordConfirm) return "Passwords do not match.";

        return null;
    };

    async function handleSubmit(e: Event) {
        e.preventDefault();

        if (isSubmitting) return;

        error = validate();
        if (error) return;

        isSubmitting = true;

        try {
            const csrf = getCsrfToken();

            // Backend endpoint to implement:
            //   POST /register
            // Body:
            //   {
            //     organization: { name, slug },
            //     user: { name, email, password }
            //   }
            //
            // Expected behavior:
            // - create org (tenant schema org_<slug>)
            // - create owner membership for the user
            // - create the user
            // - optionally log them in (session) and return redirect_to
            const res = await fetch("/register", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({
                    organization: {
                        name: orgName.trim(),
                        slug: orgSlug.trim(),
                    },
                    user: {
                        name: ownerName.trim(),
                        email: email.trim().toLowerCase(),
                        password,
                    },
                }),
            });

            if (!res.ok) {
                const text = await res.text().catch(() => "");
                error =
                    text?.trim() ||
                    (res.status === 409
                        ? "That organization slug is already taken."
                        : `Registration failed (${res.status}).`);
                return;
            }

            // Prefer JSON redirect_to if the backend returns it (even without Accept header).
            let redirectTo: string | null = null;

            try {
                const data = await res.json().catch(() => null);
                const candidate = (data as any)?.redirect_to;
                if (typeof candidate === "string" && candidate.trim() !== "") {
                    redirectTo = candidate;
                }
            } catch (_err) {
                // ignore
            }

            // If the backend logs the user in, this can go straight to /dashboard.
            // If the backend requires email confirmation, redirect_to could be /login.
            window.location.href = redirectTo ?? "/dashboard";
        } catch (err: any) {
            error = err?.message ?? "Registration failed.";
        } finally {
            isSubmitting = false;
        }
    }
</script>

<svelte:head>
    <title>{title} • FleetPrompt</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground">
    <header
        class="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60"
    >
        <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
            <div class="flex h-14 items-center justify-between">
                <a
                    use:inertia
                    href="/"
                    class="flex h-14 items-center gap-2 font-semibold tracking-tight"
                    aria-label="FleetPrompt Home"
                >
                    <img
                        src={resolveLogoWithTextUrl()}
                        alt="FleetPrompt"
                        class="h-full w-auto object-contain block"
                    />
                </a>

                <a
                    use:inertia
                    href="/login"
                    class="text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                    Sign in
                </a>
            </div>
        </div>
    </header>

    <main class="mx-auto max-w-xl px-4 py-10 sm:py-14">
        <div
            class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8"
        >
            <div class="mb-6">
                <h1 class="text-2xl font-semibold tracking-tight">{title}</h1>
                <p class="mt-1 text-sm text-muted-foreground">
                    Create an organization and an owner account. You can invite
                    teammates after setup.
                </p>
            </div>

            {#if error}
                <div
                    class="mb-5 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
                >
                    {error}
                </div>
            {/if}

            <form class="space-y-6" onsubmit={handleSubmit}>
                <section class="space-y-4">
                    <div class="text-sm font-semibold text-foreground">
                        Organization
                    </div>

                    <div class="space-y-2">
                        <label class="text-sm font-medium" for="orgName"
                            >Name</label
                        >
                        <input
                            id="orgName"
                            name="orgName"
                            type="text"
                            autocomplete="organization"
                            class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                                   ring-offset-background placeholder:text-muted-foreground
                                   focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                            bind:value={orgName}
                            disabled={isSubmitting}
                            required
                            placeholder="Acme Inc."
                        />
                    </div>

                    <div class="space-y-2">
                        <label class="text-sm font-medium" for="orgSlug"
                            >Slug</label
                        >
                        <input
                            id="orgSlug"
                            name="orgSlug"
                            type="text"
                            autocomplete="off"
                            class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                                   ring-offset-background placeholder:text-muted-foreground
                                   focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                            bind:value={orgSlug}
                            disabled={isSubmitting}
                            required
                            placeholder="acme"
                        />
                        <p class="text-xs text-muted-foreground">
                            Used to create your tenant schema
                            <code class="rounded bg-muted px-1 py-0.5"
                                >org_{orgSlug.trim() || "your_slug"}</code
                            >.
                        </p>
                    </div>
                </section>

                <div class="h-px bg-border"></div>

                <section class="space-y-4">
                    <div class="text-sm font-semibold text-foreground">
                        Owner account
                    </div>

                    <div class="space-y-2">
                        <label class="text-sm font-medium" for="ownerName"
                            >Your name</label
                        >
                        <input
                            id="ownerName"
                            name="ownerName"
                            type="text"
                            autocomplete="name"
                            class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                                   ring-offset-background placeholder:text-muted-foreground
                                   focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                            bind:value={ownerName}
                            disabled={isSubmitting}
                            required
                            placeholder="Jane Doe"
                        />
                    </div>

                    <div class="space-y-2">
                        <label class="text-sm font-medium" for="email"
                            >Email</label
                        >
                        <input
                            id="email"
                            name="email"
                            type="email"
                            autocomplete="email"
                            class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                                   ring-offset-background placeholder:text-muted-foreground
                                   focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                            bind:value={email}
                            disabled={isSubmitting}
                            required
                            placeholder="admin@acme.com"
                        />
                    </div>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div class="space-y-2">
                            <label class="text-sm font-medium" for="password"
                                >Password</label
                            >
                            <input
                                id="password"
                                name="password"
                                type="password"
                                autocomplete="new-password"
                                class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                                       ring-offset-background placeholder:text-muted-foreground
                                       focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                                bind:value={password}
                                disabled={isSubmitting}
                                required
                            />
                        </div>

                        <div class="space-y-2">
                            <label
                                class="text-sm font-medium"
                                for="passwordConfirm">Confirm</label
                            >
                            <input
                                id="passwordConfirm"
                                name="passwordConfirm"
                                type="password"
                                autocomplete="new-password"
                                class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                                       ring-offset-background placeholder:text-muted-foreground
                                       focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                                bind:value={passwordConfirm}
                                disabled={isSubmitting}
                                required
                            />
                        </div>
                    </div>

                    <p class="text-xs text-muted-foreground">
                        After registration, your membership role should be
                        <code class="rounded bg-muted px-1 py-0.5">owner</code>
                        for this organization.
                    </p>
                </section>

                <button
                    type="submit"
                    class="inline-flex w-full items-center justify-center rounded-md text-sm font-medium transition-colors
                           bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4
                           disabled:opacity-60 disabled:pointer-events-none"
                    disabled={isSubmitting}
                >
                    {#if isSubmitting}
                        Creating…
                    {:else}
                        Create organization
                    {/if}
                </button>

                <p class="text-center text-xs text-muted-foreground">
                    Already have an account?
                    <a
                        use:inertia
                        href="/login"
                        class="text-foreground hover:underline underline-offset-4"
                    >
                        Sign in
                    </a>
                </p>
            </form>
        </div>

        <p class="mt-6 text-center text-xs text-muted-foreground">
            Registration creates both an organization and a user. The backend
            must implement <code class="rounded bg-muted px-1 py-0.5"
                >POST /register</code
            >.
        </p>
    </main>
</div>
