import { defineConfig } from "vite";

// In dev, /api is proxied to the FastAPI backend; in the container nginx does it.
export default defineConfig({
  server: { proxy: { "/api": "http://localhost:8000" } },
  build: { outDir: "dist", emptyOutDir: true },
});
