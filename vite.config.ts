import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: { port: 1420, strictPort: true, watch: {ignored: ['**/target/**','**/release/**','**/*.local.env']} },
  build: { target: "es2022", sourcemap: false },
});
