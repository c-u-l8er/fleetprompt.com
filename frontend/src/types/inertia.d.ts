declare module "@inertiajs/svelte" {
  /**
   * Minimal typings to satisfy TypeScript for the Inertia Svelte adapter.
   * This is intentionally lightweight; expand as needed as you adopt more APIs.
   */

  export type InertiaPage = {
    component: string;
    props: Record<string, unknown>;
    url: string;
    version?: string | null;
    [key: string]: unknown;
  };

  export type InertiaAppSetupProps = {
    el: Element;
    App: unknown;
    props: Record<string, unknown>;
  };

  export type CreateInertiaAppOptions = {
    page?: InertiaPage;
    resolve: (name: string) => unknown | Promise<unknown>;
    setup: (args: InertiaAppSetupProps) => unknown;
    progress?: Record<string, unknown> | false;
  };

  export function createInertiaApp(options: CreateInertiaAppOptions): Promise<void> | void;

  /**
   * Svelte action for client-side navigation:
   *   <a use:inertia href="/path">...</a>
   */
  export const inertia: (node: Element, options?: Record<string, unknown>) => {
    destroy?: () => void;
    update?: (options?: Record<string, unknown>) => void;
  };
}
