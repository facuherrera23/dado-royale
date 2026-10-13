# 🎲 Dado Royale

**En vivo:** <https://facuherrera23.github.io/dado-royale/> · **Repo:** <https://github.com/facuherrera23/dado-royale>

Juego web de **dados multijugador con apuestas entre jugadores usando fichas virtuales** (sin dinero real ni pasarelas de pago).

## Arquitectura

- **Frontend:** Vite 8 + React 19 + TypeScript 5.9 (strict), Tailwind CSS 4, TanStack Query 5 (estado de servidor), Zustand (sesión), React Router 7 (**HashRouter**), Framer Motion, Zod.
- **Backend:** Supabase (PostgreSQL, Auth, Realtime, RLS). **Toda la lógica de juego y de fichas vive en funciones SQL `SECURITY DEFINER`**: el cliente nunca calcula dados, saldos ni pagos.
- **Despliegue:** GitHub Pages con GitHub Actions (por eso `HashRouter`: Pages no soporta rewrites de SPA).
- **Tests:** Vitest (frontend) y pgTAP (tests SQL de esquema, RLS, motor de juego y auditoría de seguridad), ambos en CI.

```
src/
  app/                # Providers, router (lazy por ruta), AppShell
  features/
    auth/             # Login/registro (Zod), guards, store de sesión
    lobby/            # Mesas en tiempo real, unirse/salir
    table/            # Ronda: dados animados, pozo, historial
    wallet/           # Saldo, faucet con cooldown, ledger paginado
    ranking/          # Leaderboard
    admin/            # Panel admin (protegido por RLS + RPC)
    legal/            # Términos y juego responsable
  lib/                # Cliente Supabase único, env validado, useConfig
  test/               # Setup de Vitest
supabase/
  migrations/         # Migraciones SQL versionadas
  tests/database/     # Tests pgTAP (61 aserciones)
.github/workflows/    # ci.yml (lint+build+tests+pgTAP) y deploy.yml (Pages)
```

## Desarrollo local

**Requisitos:** Node 24+, Docker Desktop, npm.

```bash
npm install
npx supabase start      # levanta PostgreSQL, Auth, Realtime, PostgREST en Docker
                          # (aplica automáticamente todas las migraciones)
npm run dev             # http://127.0.0.1:5173
```

El `.env` por defecto apunta al stack local (claves públicas del stack de desarrollo, no sensibles). Studio local: <http://127.0.0.1:54323>.

## Scripts

| Comando                 | Descripción                      |
| ----------------------- | -------------------------------- |
| `npm run dev`           | Servidor de desarrollo           |
| `npm run build`         | Typecheck + build de producción  |
| `npm run lint`          | ESLint (strictTypeChecked)       |
| `npm run format`        | Prettier                         |
| `npm test`              | Vitest (frontend)                |
| `npx supabase test db`  | Tests SQL (pgTAP): 61 aserciones |
| `npx supabase db reset` | Resetea y repuebla la BD local   |

## Reglas del juego (motor SQL)

**Cinco juegos:** 🎲 Dados (2d6), 🃏 Póker de 2 cartas, ♠ Blackjack (21 vs la banca), 🗡️ Guerra de cartas (1 carta, gana la más alta) y ✊ Piedra-Papel-Tijera (elección secreta en tabla oculta, piedra>tijeras>papel>piedra). Todos comparten pozo, comisión del 4% (PvP), desempates y reembolsos; blackjack no tiene comisión (la banca cobra las perdedoras).

- **Dados:** 2d6 por jugador, generados en el servidor con `pgcrypto.gen_random_bytes` y **rejection sampling sin sesgo**. Nunca `random()`, nunca en el cliente.
- **Póker 2 cartas:** baraja única de 52 por ronda (`draw_card` con muestreo uniforme criptográfico, **sin repetición**). Victoria: pareja > carta alta, con kicker (`hand_score`). Los empatados reciben cartas nuevas.
- **Blackjack (21):** vs la banca, con **apuesta variable** (`set_bet` dentro del rango min–max de la mesa; solo entran en la mano los sentados con apuesta fijada). Acciones `bj_action(..., action, hand)`: **hit, stand, doblar** (×2, una carta y plantarse), **separar parejas** (crea una segunda mano con apuesta igual, balance suficiente exigido) y **seguro** (si la banca muestra As: la mitad de la apuesta, paga 2:1 si la banca tiene natural). Contabilidad: la stake siempre entra a la casa y cada payout/refund tiene su espejo negativo (`house_settlement`) → el ledger cuadra a 0. La banca **roba hasta 17**; natural paga 3:2; push = reembolso íntegro.
- **Carta oculta de la banca (real):** la segunda carta de la banca se guarda en `round_dealer_holes`, una tabla **sin ningún permiso para la API ni publicación en Realtime** (`SELECT` denegado 42501, verificado por test). Solo las funciones SECURITY DEFINER la tocan, y al liquidar la ronda la carta se funde en `rounds.dealer_cards` y el hueco se borra.
- **Cron:** con `pg_cron`, `cancel_stale_rounds()` se ejecuta cada 5 minutos y reembolsa rondas atascadas sin actividad (si pg_cron no estuviera disponible, el mismo efecto lo da `cancel_round` tras el timeout).
- **Inicio:** cualquier jugador sentado llama `start_round(table_id)`; con ≥ `min_players` (2) se crea la ronda y se bloquean las apuestas (`bet_lock`) de todos los sentados en **una sola transacción**. Una ronda por mesa.
- **Resolución:** cada jugador tira sus dados con `roll_round(round_id)`; al completar todos: gana el total más alto.
- **Comisión:** `house_fee = floor(pozo × 4 / 100)`. **Redondeo a favor del jugador**: `payout = pozo − house_fee` y ambos suman exactamente el pozo.
- **Empates:** re-lanzan solo los empatados, hasta 3 desempates; si persiste: `refund` íntegro **sin comisión** y ronda `cancelled`.
- **Desconexión:** `cancel_round(round_id)` reembolsa rondas atascadas más de 300s.
- **Contabilidad:** el ledger (inmutable, sin UPDATE/DELETE) cuadra a 0 por ronda; la comisión se asienta en `house_account` y como fila `house_fee`.
- **Idempotencia:** claves `bet:` / `payout:` / `housefee:` / `refund:` / `faucet:` únicas — las llamadas repetidas jamás duplican fichas.

Config ajustable sin código en la tabla `config`: `house_fee_percent`, `faucet_amount`, `faucet_cooldown_hours`, `min_players`, `max_tiebreaks`, `join_cooldown_seconds`, `round_timeout_seconds`.

## Seguridad (checklist verificado por tests — `007_sec_audit.test.sql`)

- **KYC (18+):** `submit_kyc` valida nombre completo, mayoría de edad y país ISO; el documento se guarda solo como hash SHA-256. `join_table`/`set_bet` exigen `kyc_verified` (código P0035): sin verificación no se puede jugar.

1. ✅ El frontend solo usa la `anon key`; la `service_role` **no existe** en el repo ni en `VITE_*`.
2. ✅ RLS activado en las 9 tablas; `wallets/ledger/rounds/round_players/table_players/tables/config/house_account` sin INSERT/UPDATE/DELETE para `authenticated`/`anon`.
3. ✅ Las 8 RPC públicas son `SECURITY DEFINER` con `search_path = public` y `EXECUTE` solo para `authenticated`; `roll_d6()` es interna (sin EXECUTE).
4. ✅ Saldo entero, `CHECK (balance >= 0)`, ledger inmutable e idempotente.
5. ✅ Rate limiting en faucet (24h) y en unirse/salir de mesa (5s).
6. ✅ Prueba de ataque (`005_security.test.sql`): un usuario autenticado NO puede alterar saldos, dados, ledger ni la casa desde la API.
7. ✅ `.env` y `.env.*` en `.gitignore`; solo `.env.example` versionado.
8. ✅ Admin protegido por RLS + `get_admin_stats()` (P0403), no solo por la UI.

## Desplegar en GitHub Pages

1. **Sube el repo** a GitHub (`main`).
2. **Aplica las migraciones al proyecto real** (una sola vez; pide la **DB password** del panel de Supabase, que solo tú conoces — nunca la compartas ni la subas al repo):
   ```bash
   npx supabase login                                   # token de acceso personal
   npx supabase link --project-ref cjalkhrmuxndrozcwcmo # pidió la DB password
   npx supabase db push                                 # aplica supabase/migrations/*
   ```
3. **GitHub Secrets** (Settings → Secrets and variables → Actions):
   - `VITE_SUPABASE_URL` = `https://cjalkhrmuxndrozcwcmo.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = la anon key del proyecto
4. **Activa Pages**: Settings → Pages → Source: **GitHub Actions**.
5. **Auth en Supabase** (dashboard → Authentication → URL Configuration):
   - Site URL: `https://<tu-usuario>.github.io/<repo>/`
   - Redirect URLs: añade la misma URL con `/#/` (p. ej. `https://<tu-usuario>.github.io/<repo>/#/`).
6. Haz push a `main`: el workflow `deploy.yml` construye con `BASE_PATH=/<repo>/` y publica.
7. Promociona un admin en producción (SQL Editor del dashboard):
   ```sql
   update public.profiles set is_admin = true where username = 'tu_usuario';
   ```
8. **(Opcional) OAuth con Google:**
   - Google Cloud Console → crea un OAuth Client ID tipo "Web" con redirect: `https://cjalkhrmuxndrozcwcmo.supabase.co/auth/v1/callback`
   - Supabase → Authentication → Providers → **Google**: pega Client ID/Secret y actívalo.
   - El botón "Continuar con Google" del login funcionará en cuanto esté configurado.

## Avisos legales

Las fichas son **virtuales y sin valor monetario**. Solo mayores de 18 años. Términos completos en la app (`/terminos`).
