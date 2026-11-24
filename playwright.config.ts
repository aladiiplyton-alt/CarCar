import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests",
  fullyParallel: true,
  workers: 2,
  timeout: 60000,
  webServer: {
    command: "npm run dev",
    url: "http://127.0.0.1:1420",
    reuseExistingServer: true,
    timeout: 60000,
  },
  use: {
    baseURL: "http://127.0.0.1:1420",
    viewport: { width: 600, height: 710 },
    channel: "chrome",
  },
  reporter: "list",
});
