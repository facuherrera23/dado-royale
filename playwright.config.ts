import { defineConfig, devices } from '@playwright/test';

/**
 * E2E contra el stack local de Supabase (Docker) + Vite dev server.
 * Requiere: `npx supabase start` corriendo.
 */
export default defineConfig({
  testDir: './e2e',
  timeout: 90000,
  retries: 1,
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://127.0.0.1:5173',
    trace: 'only-on-failure',
    headless: true,
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
});
