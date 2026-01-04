import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: {
      $lib: path.resolve(__dirname, "./src/lib"),
    },
  },
  build: {
    // Build directly into the Phoenix app's static assets dir
    outDir: path.resolve(__dirname, "../backend/priv/static/assets"),
    emptyOutDir: true,
    manifest: true,
    rollupOptions: {
      input: {
        app: path.resolve(__dirname, "./src/app.ts"),
      },
      output: {
        entryFileNames: "[name].js",
        chunkFileNames: "[name].js",
        assetFileNames: "[name].[ext]",
      },
    },
  },
});
