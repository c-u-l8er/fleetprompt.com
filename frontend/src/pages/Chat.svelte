<script lang="ts">
    import AppShell from "../lib/components/AppShell.svelte";

    type ChatRole = "user" | "assistant";

    type ChatMessage = {
        id: string;
        role: ChatRole;
        content: string;
        actions?: Array<{
            type: string;
            id?: string;
            label?: string;
            data?: Record<string, unknown>;
        }>;
        inserted_at?: string;
    };

    type SseEvent =
        | { type: "start"; at?: string }
        | { type: "chunk"; chunk: string }
        | {
              type: "complete";
              message: ChatMessage;
              meta?: Record<string, unknown>;
          }
        | { type: string; [key: string]: unknown };

    export let initialMessages: ChatMessage[] = [];

    // Shared props (provided by the backend via Inertia shared props)
    export let user: {
        id?: string | null;
        name?: string | null;
        email?: string | null;
        role?: string | null;
    } | null = null;

    // Tenant context (slug + full schema name)
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

    // Optional: provide tenant-scoped agents so Chat can offer an agent selector UI.
    // Shape is intentionally minimal (id + name).
    export let agents: Array<{
        id: string;
        name: string;
    }> | null = null;

    // Optional: backend can suggest a default agent for this chat session.
    export let default_agent_id: string | null = null;

    let messages: ChatMessage[] = initialMessages ?? [];
    let input = "";
    let isStreaming = false;
    let streamingMessage: ChatMessage | null = null;
    let errorMessage: string | null = null;

    // Selected tenant-scoped Agent UUID to run executions against.
    let agentId = "";

    // Default the agent id (only if you haven't picked/typed one yet):
    // 1) `default_agent_id` from backend props
    // 2) first agent from `agents` list
    $: if (!agentId.trim()) {
        const fromProp = (default_agent_id ?? "").trim();
        if (fromProp) {
            agentId = fromProp;
        } else if (agents && agents.length > 0 && agents[0]?.id) {
            agentId = agents[0].id;
        }
    }

    type InstallState = "idle" | "installing" | "installed" | "failed";
    let installState: InstallState = "idle";
    let installingSlug: string | null = null;
    let installMessage: string | null = null;

    async function installStarterPackage(slug: string) {
        if (!slug || installState === "installing") return;

        installState = "installing";
        installingSlug = slug;
        installMessage = null;
        errorMessage = null;

        const csrf =
            document
                .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
                ?.getAttribute("content") ?? "";

        try {
            const res = await fetch("/marketplace/install", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({ slug }),
            });

            const text = await res.text().catch(() => "");
            const parsed = text ? JSON.parse(text) : null;

            if (!res.ok) {
                throw new Error(
                    parsed?.error ||
                        `Install request failed (${res.status}): ${text || res.statusText}`,
                );
            }

            if (!parsed?.ok) {
                throw new Error(
                    parsed?.error || "Install request did not succeed.",
                );
            }

            // Poll install status until installed (or timeout).
            const startedAt = Date.now();
            const maxWaitMs = 45_000;

            while (Date.now() - startedAt < maxWaitMs) {
                const statusRes = await fetch(
                    "/marketplace/installations/status",
                    {
                        method: "GET",
                        headers: { Accept: "application/json" },
                    },
                );

                if (!statusRes.ok) {
                    // Don't hard-fail on polling issues; keep waiting briefly.
                    await new Promise((r) => setTimeout(r, 750));
                    continue;
                }

                const statusJson = (await statusRes
                    .json()
                    .catch(() => null)) as any;
                const entry = statusJson?.installation_status?.[slug];
                const status = entry?.status;

                // Status comes from Ash; expect string-ish values like "installed"/"installing"/"failed".
                if (status === "installed") {
                    installState = "installed";
                    installMessage =
                        "Installed. Reloading to pick up newly created agents…";
                    // Reload to re-fetch /chat props (agents list).
                    setTimeout(() => window.location.reload(), 400);
                    return;
                }

                if (status === "failed") {
                    installState = "failed";
                    installMessage =
                        entry?.last_error ||
                        "Install failed (see Marketplace status / Signals for details).";
                    return;
                }

                await new Promise((r) => setTimeout(r, 750));
            }

            installState = "failed";
            installMessage =
                "Install is taking longer than expected. Check Marketplace install status, then refresh.";
        } catch (err: any) {
            installState = "failed";
            installMessage = err?.message ?? "Install failed.";
        } finally {
            if (installState !== "installing") {
                installingSlug = null;
            }
        }
    }

    let messagesContainer: HTMLDivElement | null = null;
    let textareaEl: HTMLTextAreaElement | null = null;

    let currentStreamAbort: AbortController | null = null;

    const nowIso = () => new Date().toISOString();
    const uid = (prefix: string) =>
        `${prefix}_${Date.now()}_${Math.random().toString(16).slice(2)}`;

    function scrollToBottom() {
        if (!messagesContainer) return;
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }

    function autoResize() {
        if (!textareaEl) return;
        textareaEl.style.height = "auto";
        textareaEl.style.height = `${Math.min(textareaEl.scrollHeight, 240)}px`;
    }

    function sseExtractJsonPayloads(rawEvent: string): string[] {
        // Support:
        // - "data: {...}\n\n"
        // - multiple data lines per event (concat with "\n")
        const lines = rawEvent.split("\n");
        const dataLines = lines
            .filter((l) => l.startsWith("data:"))
            .map((l) => l.slice("data:".length).trimStart());

        if (dataLines.length === 0) return [];
        return [dataLines.join("\n")];
    }

    function applySseEvent(evt: SseEvent) {
        if (evt.type === "chunk" && typeof evt.chunk === "string") {
            if (!streamingMessage) {
                streamingMessage = {
                    id: uid("assistant_stream"),
                    role: "assistant",
                    content: evt.chunk,
                    actions: [],
                    inserted_at: nowIso(),
                };
            } else {
                streamingMessage = {
                    ...streamingMessage,
                    content: (streamingMessage.content ?? "") + evt.chunk,
                };
            }
            queueMicrotask(scrollToBottom);
            return;
        }

        if (
            evt.type === "complete" &&
            evt.message &&
            typeof evt.message === "object"
        ) {
            const final = evt.message as ChatMessage;

            messages = [...messages, final];
            streamingMessage = null;
            isStreaming = false;
            queueMicrotask(scrollToBottom);
            return;
        }

        // Ignore unknown event types for now.
    }

    async function sendMessage(e?: Event) {
        e?.preventDefault?.();

        const content = input.trim();
        if (!content || isStreaming) return;

        const trimmedAgentId = agentId.trim();
        if (!trimmedAgentId) {
            if (!agents || agents.length === 0) {
                errorMessage =
                    "No agents are available yet for this tenant. Install a starter package below (recommended), or create an agent in Admin → Agents.";
            } else {
                errorMessage =
                    "Select an agent first (tenant-scoped). You can also manage agents in AshAdmin under Agents.";
            }
            return;
        }

        errorMessage = null;

        const userMsg: ChatMessage = {
            id: uid("user"),
            role: "user",
            content,
            actions: [],
            inserted_at: nowIso(),
        };

        messages = [...messages, userMsg];
        input = "";
        autoResize();
        queueMicrotask(scrollToBottom);

        // Cancel any previous run/poll (defensive).
        if (currentStreamAbort) {
            currentStreamAbort.abort();
            currentStreamAbort = null;
        }

        const abort = new AbortController();
        currentStreamAbort = abort;

        isStreaming = true;
        streamingMessage = null;

        try {
            const csrf =
                document
                    .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
                    ?.getAttribute("content") ?? "";

            // 1) Create an execution
            const createRes = await fetch("/executions", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    Accept: "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({
                    agent_id: trimmedAgentId,
                    input: content,
                    // Optional tuning knobs; keep conservative defaults for now.
                    max_tokens: 800,
                    temperature: 0.3,
                }),
                signal: abort.signal,
            });

            if (!createRes.ok) {
                const text = await createRes.text().catch(() => "");
                throw new Error(
                    `Execution create failed (${createRes.status}): ${text || createRes.statusText}`,
                );
            }

            const created = (await createRes.json().catch(() => null)) as any;
            const executionId: string | undefined = created?.execution?.id;

            if (!executionId) {
                throw new Error(
                    "Execution create succeeded but no execution.id was returned.",
                );
            }

            // 2) Poll execution status until terminal
            const startedAt = Date.now();
            const maxWaitMs = 90_000;

            while (true) {
                if (abort.signal.aborted) break;

                const pollRes = await fetch(
                    `/executions/${executionId}/status`,
                    {
                        method: "GET",
                        headers: {
                            Accept: "application/json",
                        },
                        signal: abort.signal,
                    },
                );

                if (!pollRes.ok) {
                    const text = await pollRes.text().catch(() => "");
                    throw new Error(
                        `Execution poll failed (${pollRes.status}): ${text || pollRes.statusText}`,
                    );
                }

                const polled = (await pollRes.json().catch(() => null)) as any;
                const state: string | undefined = polled?.execution?.state;
                const output: string | undefined = polled?.execution?.output;
                const errText: string | undefined = polled?.execution?.error;

                // Simple UI affordance while running.
                streamingMessage = {
                    id: uid("assistant_stream"),
                    role: "assistant",
                    content:
                        state && (state === "queued" || state === "running")
                            ? `Running (${state})…`
                            : "Running…",
                    actions: [],
                    inserted_at: nowIso(),
                };

                queueMicrotask(scrollToBottom);

                if (state === "succeeded") {
                    const assistantMsg: ChatMessage = {
                        id: uid("assistant"),
                        role: "assistant",
                        content: (output ?? "").trim() || "(empty response)",
                        actions: [],
                        inserted_at: nowIso(),
                    };

                    messages = [...messages, assistantMsg];
                    streamingMessage = null;
                    break;
                }

                if (state === "failed") {
                    streamingMessage = null;
                    errorMessage = errText || "Execution failed.";
                    break;
                }

                if (state === "canceled") {
                    streamingMessage = null;
                    errorMessage = "Execution was canceled.";
                    break;
                }

                if (Date.now() - startedAt > maxWaitMs) {
                    streamingMessage = null;
                    errorMessage =
                        "Execution is taking longer than expected. Keep the page open and try polling again.";
                    break;
                }

                await new Promise((r) => setTimeout(r, 650));
            }
        } catch (err: any) {
            const aborted =
                err?.name === "AbortError" ||
                (typeof err?.message === "string" &&
                    err.message.toLowerCase().includes("abort"));

            if (!aborted) {
                errorMessage = err?.message ?? "Execution request failed.";
            }
        } finally {
            isStreaming = false;
            currentStreamAbort = null;
            queueMicrotask(scrollToBottom);
        }
    }

    function handleKeyDown(e: KeyboardEvent) {
        if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            void sendMessage();
        }
    }

    function stopStreaming() {
        if (currentStreamAbort) {
            currentStreamAbort.abort();
            currentStreamAbort = null;
        }
        isStreaming = false;

        if (streamingMessage) {
            messages = [...messages, streamingMessage];
            streamingMessage = null;
        }
    }
</script>

<svelte:head>
    <title>Chat • FleetPrompt</title>
</svelte:head>

<AppShell
    title="Chat"
    subtitle="Agent execution chat — POST /executions + poll GET /executions/:id/status"
    showAdminLink={true}
    {user}
    {tenant}
    {tenant_schema}
    {organizations}
    {current_organization}
>
    <div
        class="h-[calc(100vh-10.5rem)] flex flex-col rounded-2xl border border-border bg-card text-card-foreground overflow-hidden"
    >
        <div class="border-b border-border bg-background/60">
            <div class="px-4 py-3 flex items-center justify-between gap-3">
                <div class="min-w-0">
                    <div class="text-sm font-semibold truncate">
                        FleetPrompt Chat
                    </div>
                    <div class="text-xs text-muted-foreground truncate">
                        {#if isStreaming}
                            Streaming response…
                        {:else}
                            Ask anything (demo stream for now)
                        {/if}
                    </div>
                </div>

                <div class="flex items-center gap-2">
                    {#if agents && agents.length > 0}
                        <select
                            bind:value={agentId}
                            class="hidden sm:block w-[22rem] h-9 rounded-md border border-border bg-background px-3 text-sm
                   placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
                            disabled={isStreaming}
                            title="Select a tenant-scoped agent to run executions against."
                        >
                            {#each agents as a (a.id)}
                                <option value={a.id}>{a.name}</option>
                            {/each}
                        </select>
                    {:else}
                        <div class="hidden sm:flex items-center gap-2">
                            <button
                                type="button"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3 disabled:opacity-60 disabled:cursor-not-allowed"
                                disabled={installState === "installing" ||
                                    isStreaming}
                                on:click={() =>
                                    void installStarterPackage(
                                        "starter-agents",
                                    )}
                                title="Installs the Starter Agents package into your tenant (creates agents)."
                            >
                                {#if installState === "installing" && installingSlug === "starter-agents"}
                                    Installing…
                                {:else}
                                    Install Starter agents
                                {/if}
                            </button>

                            <button
                                type="button"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:cursor-not-allowed"
                                disabled={installState === "installing" ||
                                    isStreaming}
                                on:click={() =>
                                    void installStarterPackage(
                                        "customer-support",
                                    )}
                                title="Installs the Customer Support Hub package into your tenant (creates agents)."
                            >
                                {#if installState === "installing" && installingSlug === "customer-support"}
                                    Installing…
                                {:else}
                                    Install Customer Support agents
                                {/if}
                            </button>

                            <button
                                type="button"
                                class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:cursor-not-allowed"
                                disabled={installState === "installing" ||
                                    isStreaming}
                                on:click={() =>
                                    void installStarterPackage("field-service")}
                                title="Installs the Field Service Management package into your tenant (creates agents)."
                            >
                                {#if installState === "installing" && installingSlug === "field-service"}
                                    Installing…
                                {:else}
                                    Install Field Service agents
                                {/if}
                            </button>
                        </div>
                    {/if}

                    {#if isStreaming}
                        <button
                            type="button"
                            on:click={stopStreaming}
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3"
                        >
                            Stop
                        </button>
                    {/if}

                    <a
                        href="/admin/tenant"
                        class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                   bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3"
                        title="AshAdmin runs on LiveView; select tenant to browse tenant-scoped resources like Agents."
                    >
                        Admin
                    </a>
                </div>
            </div>

            {#if errorMessage}
                <div class="px-4 pb-3">
                    <div
                        class="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
                    >
                        {errorMessage}
                    </div>
                </div>
            {/if}
        </div>

        <div
            class="flex-1 overflow-y-auto px-4 py-4 space-y-4"
            bind:this={messagesContainer}
        >
            {#if !agents || agents.length === 0}
                <div class="rounded-xl border border-border bg-background p-4">
                    <div class="text-sm font-semibold">
                        No agents found for this tenant
                    </div>
                    <div class="mt-1 text-sm text-muted-foreground">
                        Chat runs through a tenant-scoped Agent. The fastest fix
                        is to install a starter package that includes agents.
                    </div>

                    <div class="mt-3 flex flex-wrap gap-2">
                        <button
                            type="button"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     bg-primary text-primary-foreground hover:bg-primary/90 h-9 px-3 disabled:opacity-60 disabled:cursor-not-allowed"
                            disabled={installState === "installing" ||
                                isStreaming}
                            on:click={() =>
                                void installStarterPackage("starter-agents")}
                            title="Installs the Starter Agents package into your tenant (creates agents)."
                        >
                            {#if installState === "installing" && installingSlug === "starter-agents"}
                                Installing…
                            {:else}
                                Install Starter agents
                            {/if}
                        </button>

                        <button
                            type="button"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:cursor-not-allowed"
                            disabled={installState === "installing" ||
                                isStreaming}
                            on:click={() =>
                                void installStarterPackage("customer-support")}
                            title="Installs the Customer Support Hub package into your tenant (creates agents)."
                        >
                            {#if installState === "installing" && installingSlug === "customer-support"}
                                Installing…
                            {:else}
                                Install Customer Support agents
                            {/if}
                        </button>

                        <button
                            type="button"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3 disabled:opacity-60 disabled:cursor-not-allowed"
                            disabled={installState === "installing" ||
                                isStreaming}
                            on:click={() =>
                                void installStarterPackage("field-service")}
                            title="Installs the Field Service Management package into your tenant (creates agents)."
                        >
                            {#if installState === "installing" && installingSlug === "field-service"}
                                Installing…
                            {:else}
                                Install Field Service agents
                            {/if}
                        </button>

                        <a
                            href="/marketplace"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3"
                        >
                            Open Marketplace
                        </a>

                        <a
                            href="/admin/tenant"
                            class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                     border border-border bg-background hover:bg-muted h-9 px-3"
                            title="AshAdmin (LiveView) — select tenant then browse Agents."
                        >
                            Open Admin
                        </a>
                    </div>

                    {#if installMessage}
                        <div class="mt-3 text-sm text-muted-foreground">
                            {installMessage}
                        </div>
                    {/if}
                </div>
            {/if}

            {#if messages.length === 0}
                <div class="text-sm text-muted-foreground">
                    No messages yet. Try: <span
                        class="font-medium text-foreground">"hello"</span
                    >
                </div>
            {/if}

            {#each messages as m (m.id)}
                <div
                    class={"flex gap-3 items-start " +
                        (m.role === "user" ? "justify-end" : "")}
                >
                    {#if m.role === "assistant"}
                        <div
                            class="w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center flex-shrink-0"
                        >
                            <span class="text-xs font-semibold">FP</span>
                        </div>
                    {/if}

                    <div
                        class={"max-w-[46rem] " +
                            (m.role === "user" ? "text-right" : "text-left")}
                    >
                        <div
                            class={"rounded-2xl px-4 py-3 text-sm leading-6 whitespace-pre-wrap " +
                                (m.role === "user"
                                    ? "bg-primary text-primary-foreground rounded-tr-sm"
                                    : "bg-muted text-foreground rounded-tl-sm")}
                        >
                            {m.content}
                        </div>
                        {#if m.inserted_at}
                            <div class="mt-1 text-[11px] text-muted-foreground">
                                {new Date(m.inserted_at).toLocaleTimeString()}
                            </div>
                        {/if}
                    </div>

                    {#if m.role === "user"}
                        <div
                            class="w-8 h-8 rounded-full bg-muted flex items-center justify-center flex-shrink-0"
                        >
                            <span
                                class="text-xs font-semibold text-muted-foreground"
                                >You</span
                            >
                        </div>
                    {/if}
                </div>
            {/each}

            {#if streamingMessage}
                <div class="flex gap-3 items-start">
                    <div
                        class="w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center flex-shrink-0"
                    >
                        <span class="text-xs font-semibold">FP</span>
                    </div>

                    <div class="max-w-[46rem] text-left">
                        <div
                            class="rounded-2xl rounded-tl-sm px-4 py-3 text-sm leading-6 whitespace-pre-wrap bg-muted text-foreground"
                        >
                            {streamingMessage.content}
                        </div>
                        <div class="mt-1 text-[11px] text-muted-foreground">
                            streaming…
                        </div>
                    </div>
                </div>
            {:else if isStreaming}
                <div class="flex gap-3 items-start">
                    <div
                        class="w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center flex-shrink-0"
                    >
                        <span class="text-xs font-semibold">FP</span>
                    </div>

                    <div class="max-w-[46rem] text-left">
                        <div
                            class="rounded-2xl rounded-tl-sm px-4 py-3 text-sm leading-6 bg-muted text-foreground"
                        >
                            <span class="inline-flex gap-1 items-center">
                                <span
                                    class="w-2 h-2 bg-muted-foreground rounded-full animate-pulse"
                                ></span>
                                <span
                                    class="w-2 h-2 bg-muted-foreground rounded-full animate-pulse"
                                    style="animation-delay: 0.2s"
                                ></span>
                                <span
                                    class="w-2 h-2 bg-muted-foreground rounded-full animate-pulse"
                                    style="animation-delay: 0.4s"
                                ></span>
                            </span>
                        </div>
                    </div>
                </div>
            {/if}
        </div>

        <div class="border-t border-border bg-background p-4">
            <form class="flex gap-3 items-end" on:submit={sendMessage}>
                <div class="flex-1">
                    <label for="chat-input" class="sr-only">Message</label>
                    <textarea
                        id="chat-input"
                        bind:this={textareaEl}
                        bind:value={input}
                        rows={1}
                        placeholder="Type a message… (Enter to send, Shift+Enter for newline)"
                        class="w-full resize-none rounded-lg border border-border bg-background px-3 py-2 text-sm leading-6
                   placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
                        on:input={autoResize}
                        on:keydown={handleKeyDown}
                        disabled={isStreaming}
                    ></textarea>
                </div>

                <button
                    type="submit"
                    class="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors
                 bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4 disabled:opacity-60 disabled:cursor-not-allowed"
                    disabled={isStreaming || input.trim().length === 0}
                >
                    Send
                </button>
            </form>

            <div class="mt-2 text-xs text-muted-foreground">
                This is a demo streaming endpoint. Phase 3 will add conversation
                history and real model responses.
            </div>
        </div>
    </div>
</AppShell>
