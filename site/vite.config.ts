import path from "path";
import { fileURLToPath } from "url";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// GitHub Pages: relative base "./" works for any repo path (hash routing, no rewrites needed).
// Override for an absolute base, e.g. SITE_BASE=/retro-cabinet-kit/ npm run build
export default defineConfig({
  base: process.env.SITE_BASE || "./",
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
});
