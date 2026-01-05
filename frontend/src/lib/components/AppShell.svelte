<script lang="ts">
  import { inertia } from "@inertiajs/svelte";

  export let title: string = "FleetPrompt";
  export let subtitle: string | null = null;

  // Optional: show an admin entry point (AshAdmin is not Inertia, but it’s a useful affordance)
  export let showAdminLink: boolean = true;

  // Optional: simple user display
  export let user:
    | {
        name?: string | null;
        email?: string | null;
      }
    | null = null;

  const currentPath =
    typeof window !== "undefined" ? window.location.pathname : "";

  const isActive = (href: string) => {
    if (!currentPath) return false;
    if (href === "/") return currentPath === "/";
    return currentPath === href || currentPath.startsWith(href + "/");
  };

  const linkClass = (href: string) => {
    const base =
      "inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors";
    const active = "bg-muted text-foreground";
    const inactive =
      "text-muted-foreground hover:text-foreground hover:bg-muted/60";

    return `${base} ${isActive(href) ? active : inactive}`;
  };
</script>

<div class="min-h-screen bg-background text-foreground">
  <header class="sticky top-0 z-40 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="flex h-14 items-center justify-between gap-4">
        <div class="flex items-center gap-3 min-w-0">
          <a
            use:inertia
            href="/"
            class="flex items-center gap-2 font-semibold tracking-tight truncate"
            aria-label="FleetPrompt Home"
          >
            <span
              class="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground"
              aria-hidden="true"
            >
              FP
            </span>
            <span class="truncate">FleetPrompt</span>
          </a>

          <nav class="hidden md:flex items-center gap-1">
            <a use:inertia href="/dashboard" class={linkClass("/dashboard")}>
              Dashboard
            </a>
            <a use:inertia href="/marketplace" class={linkClass("/marketplace")}>
              Marketplace
            </a>
            <a use:inertia href="/chat" class={linkClass("/chat")}>
              Chat
            </a>

            {#if showAdminLink}
              <!-- AshAdmin (LiveView) lives outside Inertia; use plain href -->
              <a
                href="/admin/tenant"
                class="inline-flex items-center rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                Admin
              </a>
            {/if}
          </nav>
        </div>

        <div class="flex items-center gap-3">
          <slot name="nav-right">
            {#if user}
              <div class="hidden sm:flex flex-col items-end leading-tight">
                <span class="text-sm font-medium">
                  {user.name ?? user.email ?? "Signed in"}
                </span>
                {#if user.email && user.name}
                  <span class="text-xs text-muted-foreground">{user.email}</span>
                {/if}
              </div>
            {/if}
          </slot>
        </div>
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
    <div class="mb-6 flex items-start justify-between gap-4">
      <div class="min-w-0">
        <h1 class="text-2xl font-semibold tracking-tight truncate">
          {title}
        </h1>
        {#if subtitle}
          <p class="mt-1 text-sm text-muted-foreground">
            {subtitle}
          </p>
        {/if}
      </div>

      <div class="flex items-center gap-2">
        <slot name="header-actions" />
      </div>
    </div>

    <slot />
  </main>

  <footer class="border-t">
    <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 text-xs text-muted-foreground">
        <div>
          © {new Date().getFullYear()} FleetPrompt
        </div>
        <div class="flex items-center gap-4">
          <a class="hover:text-foreground transition-colors" href="/privacy">Privacy</a>
          <a class="hover:text-foreground transition-colors" href="/terms">Terms</a>
        </div>
      </div>
    </div>
  </footer>
</div>
