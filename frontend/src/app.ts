import { createInertiaApp } from "@inertiajs/svelte";
import { mount } from "svelte";
import "./app.css";

const FP_DEBUG =
  typeof window !== "undefined" &&
  new URLSearchParams(window.location.search).has("fp_debug");

if (FP_DEBUG) {
  console.info("[FleetPrompt] frontend bundle loaded", {
    url: window.location.href,
  });
}

/**
 * Only boot the Inertia client on pages that include the server-provided
 * Inertia payload (data-page). This prevents crashes if this bundle is
 * loaded on a non-Inertia page.
 */
const inertiaEl = document.querySelector<HTMLElement>("#app[data-page]");
const appEl = inertiaEl ?? document.getElementById("app");
const pagePayload = inertiaEl?.getAttribute("data-page") ?? null;

let initialPage: unknown = null;

if (pagePayload) {
  try {
    initialPage = JSON.parse(pagePayload);
  } catch (err) {
    console.error(
      "[FleetPrompt] Failed to parse Inertia payload from #app[data-page].",
      err,
      pagePayload,
    );
  }
}

if (inertiaEl && initialPage) {
  if (FP_DEBUG) {
    console.info("[FleetPrompt] Inertia boot: found #app[data-page]", {
      hasDataPage: !!pagePayload,
      dataPageLength: pagePayload?.length,
    });
  }

  createInertiaApp({
    // Make boot deterministic by explicitly providing the initial page object
    page: initialPage as any,
    resolve: (name) => {
      const pages = import.meta.glob("./pages/**/*.svelte", { eager: true });
      const pageModule = pages[`./pages/${name}.svelte`];

      if (!pageModule) {
        throw new Error(`Inertia page not found: ${name}`);
      }

      // Vite's eager glob returns the module object; Svelte page components are the default export.
      // Fall back to the module itself for compatibility with different bundler outputs.
      return (pageModule as any).default ?? pageModule;
    },
    setup({ el, App, props }) {
      const target = (el as HTMLElement | null) ?? inertiaEl;

      if (FP_DEBUG) {
        console.info("[FleetPrompt] Inertia setup()", {
          hasApp: !!App,
          propsKeys: props ? Object.keys(props) : null,
          hasTarget: !!target,
        });
      }

      if (!target) {
        throw new Error(
          "[FleetPrompt] Inertia setup() did not receive a mount element.",
        );
      }

      // Support both:
      // - Svelte 5 function components (use `mount`)
      // - constructor-based components (use `new App(...)`)
      let app: any;
      let mountedWith: "mount" | "new" | "unknown" = "unknown";

      const isConstructorComponent =
        typeof App === "function" &&
        (App as any).prototype &&
        (typeof (App as any).prototype.$destroy === "function" ||
          typeof (App as any).prototype.$set === "function");

      if (isConstructorComponent) {
        app = new (App as any)({ target, props });
        mountedWith = "new";
      } else {
        app = mount(App as any, { target, props });
        mountedWith = "mount";
      }

      if (FP_DEBUG) {
        requestAnimationFrame(() => {
          console.info("[FleetPrompt] Inertia mounted", {
            mountedWith,
            targetChildren: target.children?.length ?? null,
            targetInnerHTMLPreview: target.innerHTML?.slice(0, 200) ?? null,
          });
        });
      }

      return app;
    },
  });
} else if (appEl && !inertiaEl) {
  // We found a #app element, but it isn't an Inertia mount point.
  // This often happens when the JS bundle is loaded on a non-Inertia route or the server rendered the wrong template.
  const attrs = Array.from(appEl.attributes).map(
    (a) => `${a.name}="${a.value}"`,
  );
  console.warn(
    "[FleetPrompt] Found #app, but it is not an Inertia mount element (missing data-page attribute).",
    {
      url: window.location.href,
      appAttributes: attrs,
      appOuterHTML: appEl.outerHTML?.slice(0, 500),
    },
  );
} else if (pagePayload && !initialPage) {
  console.warn(
    "[FleetPrompt] Found #app[data-page], but it was not valid JSON. This usually means the server rendered a malformed Inertia payload.",
    { url: window.location.href, pagePayload: pagePayload.slice(0, 500) },
  );
} else if (!appEl) {
  console.warn(
    "[FleetPrompt] No #app element found. This usually means the server did not render an Inertia response for this route.",
    { url: window.location.href },
  );
}
