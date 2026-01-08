<script lang="ts">
    import { inertia } from "@inertiajs/svelte";

    // Props that the backend can pass via Inertia, if desired.
    // (e.g. to re-populate the email field or show a flash error message)
    export let title: string = "Sign in";
    export let email: string = "";
    export let error: string | null = null;

    let formEmail = email ?? "";
    let password = "";
    let rememberMe = true;
    let isSubmitting = false;

    const getCsrfToken = () =>
        document
            .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
            ?.getAttribute("content") ?? "";

    async function handleSubmit(e: Event) {
        e.preventDefault();

        if (isSubmitting) return;

        const trimmedEmail = formEmail.trim();
        if (!trimmedEmail || !password) {
            error = "Enter your email and password.";
            return;
        }

        isSubmitting = true;
        error = null;

        // This assumes you will implement a Phoenix route like:
        //   POST /login  -> sets session + redirects (or returns 204/json)
        //
        // We use fetch so we can keep the UI responsive. If your backend responds
        // with a redirect, fetch will follow it but won't change the browser URL,
        // so we explicitly navigate on success.
        try {
            const csrf = getCsrfToken();

            const res = await fetch("/login", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({
                    email: trimmedEmail,
                    password,
                    remember_me: rememberMe,
                }),
            });

            if (!res.ok) {
                // Try to read a useful message; fall back to a generic one.
                const text = await res.text().catch(() => "");
                error =
                    text?.trim() ||
                    (res.status === 401
                        ? "Invalid email or password."
                        : `Sign-in failed (${res.status}).`);
                return;
            }

            // On success, prefer the backend-provided return-to (if present).
            let redirectTo = "/dashboard";
            try {
                const data = await res.json().catch(() => null);
                const candidate = (data as any)?.redirect_to;

                if (typeof candidate === "string" && candidate.trim() !== "") {
                    redirectTo = candidate;
                }
            } catch (_err) {
                // If the response isn't JSON for any reason, fall back to dashboard.
            }

            window.location.href = redirectTo;
        } catch (err: any) {
            error = err?.message ?? "Sign-in failed.";
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
                        src="/images/logo-with-text.png"
                        alt="FleetPrompt"
                        class="h-full w-auto object-contain block"
                    />
                </a>

                <a
                    use:inertia
                    href="/"
                    class="text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                    Back to home
                </a>
            </div>
        </div>
    </header>

    <main class="mx-auto max-w-md px-4 py-10 sm:py-14">
        <div
            class="rounded-2xl border border-border bg-card text-card-foreground p-6 sm:p-8"
        >
            <div class="mb-6">
                <h1 class="text-2xl font-semibold tracking-tight">{title}</h1>
                <p class="mt-1 text-sm text-muted-foreground">
                    Use your email and password to access your organization.
                </p>
            </div>

            {#if error}
                <div
                    class="mb-5 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
                >
                    {error}
                </div>
            {/if}

            <form class="space-y-4" onsubmit={handleSubmit}>
                <div class="space-y-2">
                    <label class="text-sm font-medium" for="email">Email</label>
                    <input
                        id="email"
                        name="email"
                        type="email"
                        autocomplete="email"
                        class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                               ring-offset-background placeholder:text-muted-foreground
                               focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                        bind:value={formEmail}
                        disabled={isSubmitting}
                        required
                    />
                </div>

                <div class="space-y-2">
                    <div class="flex items-center justify-between gap-2">
                        <label class="text-sm font-medium" for="password">
                            Password
                        </label>

                        <span
                            class="text-xs text-muted-foreground"
                            title="Password reset flow not implemented yet."
                        >
                            Forgot password? (coming soon)
                        </span>
                    </div>

                    <input
                        id="password"
                        name="password"
                        type="password"
                        autocomplete="current-password"
                        class="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm
                               ring-offset-background placeholder:text-muted-foreground
                               focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                        bind:value={password}
                        disabled={isSubmitting}
                        required
                    />
                </div>

                <div class="flex items-center justify-between gap-3">
                    <label
                        class="inline-flex items-center gap-2 text-sm text-muted-foreground"
                    >
                        <input
                            type="checkbox"
                            class="h-4 w-4 rounded border border-input bg-background"
                            bind:checked={rememberMe}
                            disabled={isSubmitting}
                        />
                        Remember me
                    </label>
                </div>

                <button
                    type="submit"
                    class="inline-flex w-full items-center justify-center rounded-md text-sm font-medium transition-colors
                           bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4
                           disabled:opacity-60 disabled:pointer-events-none"
                    disabled={isSubmitting}
                >
                    {#if isSubmitting}
                        Signing in…
                    {:else}
                        Sign in
                    {/if}
                </button>

                <p class="pt-2 text-center text-xs text-muted-foreground">
                    Need an account?
                    <a
                        use:inertia
                        href="/register"
                        class="text-foreground hover:underline underline-offset-4"
                    >
                        Create one
                    </a>
                </p>
            </form>
        </div>

        <p class="mt-6 text-center text-xs text-muted-foreground">
            This is a session-based login. Once authenticated, the app header
            can display your user and selected tenant.
        </p>
    </main>
</div>
