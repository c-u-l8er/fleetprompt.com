<script lang="ts">
    import { inertia } from "@inertiajs/svelte";

    export let message: string;
</script>

<div class="min-h-screen bg-background flex items-center justify-center">
    <div class="text-center max-w-2xl px-6">
        <h1 class="text-4xl font-bold text-foreground mb-4">
            Welcome to FleetPrompt
        </h1>

        <p class="text-muted-foreground mb-8">
            {message}
        </p>

        <div class="flex items-center justify-center gap-3">
            <a
                use:inertia
                href="/dashboard"
                class="inline-flex items-center justify-center rounded-md text-sm font-medium ring-offset-background transition-colors
               focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2
               disabled:pointer-events-none disabled:opacity-50 bg-primary text-primary-foreground hover:bg-primary/90
               h-10 px-4 py-2"
            >
                Get Started
            </a>

            <a
                use:inertia
                href="/marketplace"
                class="inline-flex items-center justify-center rounded-md text-sm font-medium ring-offset-background transition-colors
               focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2
               disabled:pointer-events-none disabled:opacity-50 border border-border bg-background hover:bg-muted
               h-10 px-4 py-2"
            >
                Browse Marketplace
            </a>
        </div>

        <p class="mt-6 text-xs text-muted-foreground">
            Powered by Phoenix + Ash on the backend, and Svelte + Inertia on the
            frontend.
        </p>
    </div>
</div>
