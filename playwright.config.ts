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
  webServer: process.env.CI
    ? {
        command: 'npm run preview -- --host 127.0.0.1 --port 4173',
        url: 'http://127.0.0.1:4173',
        timeout: 120000,
      }
    : {
        command: 'npm run dev -- --host 127.0.0.1',
        url: 'http://127.0.0.1:5173',
        reuseExistingServer: true,
        timeout: 120000,
      },
});
