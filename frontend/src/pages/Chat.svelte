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

    let messages: ChatMessage[] = initialMessages ?? [];
    let input = "";
    let isStreaming = false;
    let streamingMessage: ChatMessage | null = null;
    let errorMessage: string | null = null;

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

        // Cancel any previous stream (defensive).
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

            const res = await fetch("/chat/message", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    ...(csrf ? { "X-CSRF-Token": csrf } : {}),
                },
                body: JSON.stringify({ message: content }),
                signal: abort.signal,
            });

            if (!res.ok) {
                const text = await res.text().catch(() => "");
                throw new Error(
                    `Chat request failed (${res.status}): ${text || res.statusText}`,
                );
            }

            if (!res.body) {
                throw new Error(
                    "Chat response did not include a readable stream.",
                );
            }

            const reader = res.body.getReader();
            const decoder = new TextDecoder("utf-8");

            let buffer = "";

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, { stream: true });

                // SSE events are separated by a blank line.
                const parts = buffer.split("\n\n");
                buffer = parts.pop() ?? "";

                for (const rawEvent of parts) {
                    const payloads = sseExtractJsonPayloads(rawEvent);

                    for (const payload of payloads) {
                        try {
                            const parsed = JSON.parse(payload) as SseEvent;
                            applySseEvent(parsed);
                        } catch (_err) {
                            // Ignore malformed JSON chunks; keep streaming.
                        }
                    }
                }
            }

            // If the server ended without a "complete" event, finalize whatever we have.
            if (streamingMessage) {
                messages = [...messages, streamingMessage];
                streamingMessage = null;
            }
        } catch (err: any) {
            // If aborted, don't show as an error.
            const aborted =
                err?.name === "AbortError" ||
                (typeof err?.message === "string" &&
                    err.message.toLowerCase().includes("abort"));

            if (!aborted) {
                errorMessage = err?.message ?? "Chat request failed.";
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
    subtitle="Streaming chat (SSE) — backed by POST /chat/message"
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
