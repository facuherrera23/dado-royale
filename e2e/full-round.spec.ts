import { expect, test, type APIRequestContext } from '@playwright/test';

/**
 * E2E: dos jugadores reales juegan una ronda de dados en DULANE.
 * Crea las cuentas por la API admin local (service key de desarrollo).
 */

const API = 'http://127.0.0.1:54321';
const SERVICE_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

async function createUser(request: APIRequestContext, email: string, username: string) {
  const res = await request.post(`${API}/auth/v1/admin/users`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    data: { email, password: 'Prueba1234!', email_confirm: true, user_metadata: { username } },
  });
  expect(res.ok()).toBeTruthy();
  return (await res.json()) as { id: string };
}

async function setKyc(request: APIRequestContext, uid: string) {
  await request.patch(`${API}/rest/v1/profiles?id=eq.${uid}`, {
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    data: { kyc_verified: true },
  });
}

async function grantChips(request: APIRequestContext, uid: string) {
  await request.patch(`${API}/rest/v1/wallets?user_id=eq.${uid}`, {
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    data: { balance: 10000 },
  });
}

async function login(page: import('@playwright/test').Page, email: string) {
  await page.goto('/#/auth');
  await page.getByLabel('Email').fill(email);
  await page.locator('#password').fill('Prueba1234!');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/#\/lobby/);
}

/** Crea una mesa de dados dedicada a la prueba (aisla de ruido previo). */
async function createTable(request: APIRequestContext, name: string) {
  const res = await request.post(`${API}/rest/v1/tables`, {
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    data: { name, bet_amount: 10, max_players: 6, game: 'dice' },
  });
  expect(res.ok()).toBeTruthy();
  const rows = (await res.json()) as { id: string }[];
  return rows[0].id;
}

test('dos jugadores juegan una ronda de dados en tiempo real', async ({ browser, request }) => {
  const suf = Date.now();
  const emailA = `e2e-a-${String(suf)}@test.dev`;
  const emailB = `e2e-b-${String(suf)}@test.dev`;

  const a = await createUser(request, emailA, `e2ea${String(suf % 10000)}`);
  const b = await createUser(request, emailB, `e2eb${String(suf % 10000)}`);
  await setKyc(request, a.id);
  await setKyc(request, b.id);
  await grantChips(request, a.id);
  await grantChips(request, b.id);
  const tableId = await createTable(request, `E2E Mesa ${String(suf)}`);

  const ctxA = await browser.newContext();
  const ctxB = await browser.newContext();
  const pageA = await ctxA.newPage();
  const pageB = await ctxB.newPage();

  await login(pageA, emailA);
  await login(pageB, emailB);

  // Ambos entran directo a la mesa dedicada y se sientan
  for (const page of [pageA, pageB]) {
    await page.goto(`/#/mesa/${tableId}`);
    await expect(page.getByText(/No estás sentado/)).toBeVisible({ timeout: 15000 });
  }

  // Volvemos al lobby y buscamos la mesa por nombre
  for (const page of [pageA, pageB]) {
    await page.goto('/#/lobby');
    const card = page.locator('article', { hasText: `E2E Mesa ${String(suf)}` });
    await expect(card).toBeVisible({ timeout: 15000 });
    await card.getByRole('button', { name: /Unirse por/ }).click();
    await expect(page).toHaveURL(new RegExp(`#/mesa/${tableId}`), { timeout: 15000 });
  }

  // A inicia la ronda, ambos tiran los dados
  await pageA.getByRole('button', { name: /Iniciar ronda/ }).click();
  await expect(pageA.getByText('Ronda en curso')).toBeVisible({ timeout: 15000 });
  await expect(pageB.getByText('Ronda en curso')).toBeVisible({ timeout: 15000 });

  await pageA.getByRole('button', { name: /Tirar mis dados/ }).click();
  await pageB.getByRole('button', { name: /Tirar mis dados/ }).click();

  // Re-lanzar hasta 3 veces más por si hay empate (desempates)
  for (let i = 0; i < 3; i++) {
    const result = await Promise.race([
      pageA
        .getByText(/Has ganado|Ganador:/)
        .waitFor({ state: 'visible', timeout: 8000 })
        .then(() => 'finished' as const),
      pageA
        .getByText(/Empate.*vuelven a lanzar|apuestas devueltas/)
        .waitFor({ state: 'visible', timeout: 8000 })
        .then(() => 'retry' as const),
      pageA
        .getByText('Ronda cancelada')
        .waitFor({ state: 'visible', timeout: 8000 })
        .then(() => 'cancelled' as const),
    ]).catch(() => 'timeout' as const);
    if (result !== 'retry') break;
    const btnA = pageA.getByRole('button', { name: /Tirar mis dados/ });
    if (await btnA.isVisible()) await btnA.click();
    const btnB = pageB.getByRole('button', { name: /Tirar mis dados/ });
    if (await btnB.isVisible()) await btnB.click();
  }

  // La ronda finaliza y aparece un ganador
  await expect(pageA.getByText(/Has ganado|Ganador:/)).toBeVisible({ timeout: 15000 });

  await ctxA.close();
  await ctxB.close();
});
