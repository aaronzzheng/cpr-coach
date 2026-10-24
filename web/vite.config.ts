import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev server on 5173; API and websockets proxy to the FastAPI backend on 8000.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    fs: { allow: [".."] },
    proxy: {
      "/api": "http://127.0.0.1:8000",
      "/ws": { target: "ws://127.0.0.1:8000", ws: true },
    },
  },
});
