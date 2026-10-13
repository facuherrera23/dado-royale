-- Tests de la Fase 3: claim_faucet (auth, éxito, ledger, cooldown, permisos, RLS).
begin;
select plan(8);

-- Fixture: dos usuarios con perfil y wallet
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('aaaaaaa1-0000-0000-0000-000000000001', 'fauce1@test.dev', '{"username":"fauce1"}',
        'authenticated', 'authenticated', now(), now(), now()),
       ('aaaaaaa2-0000-0000-0000-000000000002', 'fauce2@test.dev', '{"username":"fauce2"}',
        'authenticated', 'authenticated', now(), now(), now());

-- Al usuario 2 le "sembramos" un reclamo de hace 25h (como superusuario,
-- el ledger permite INSERT; lo que está prohibido es UPDATE/DELETE).
insert into public.ledger (user_id, type, amount, balance_after, idempotency_key, created_at)
values ('aaaaaaa2-0000-0000-0000-000000000002', 'faucet', 1000, 1000, 'faucet-seed-u2',
        now() - interval '25 hours');

-- -------------------------------------------------------------
set local role authenticated;

-- 1. Sin JWT (auth.uid() = null) => rechazado
select throws_ok(
  $$select public.claim_faucet()$$,
  'P0001', 'No autenticado',
  'claim_faucet rechaza llamadas sin autenticar'
);

-- Usamos el usuario 1
set local request.jwt.claims = '{"sub":"aaaaaaa1-0000-0000-0000-000000000001","role":"authenticated"}';

-- 2-3-4. Primer reclamo: devuelve saldo correcto, wallet actualizada, 1 fila en ledger
select is(
  (public.claim_faucet() ->> 'balance')::bigint,
  public.config_int('faucet_amount'),
  'claim_faucet devuelve saldo = faucet_amount de config'
);
select is(
  (select balance from public.wallets where user_id = 'aaaaaaa1-0000-0000-0000-000000000001'),
  public.config_int('faucet_amount'),
  'La wallet quedó acreditada'
);
select ok(
  exists(select 1 from public.ledger
          where user_id = 'aaaaaaa1-0000-0000-0000-000000000001'
            and type = 'faucet'
            and amount = public.config_int('faucet_amount')
            and balance_after = public.config_int('faucet_amount')),
  'El ledger registra la concesión con balance_after correcto'
);

-- 5. Segundo reclamo inmediato => cooldown
select throws_ok(
  $$select public.claim_faucet()$$,
  'P0002', null,
  'Un segundo reclamo inmediato es rechazado por cooldown'
);

-- 6. El usuario 2, con último reclamo hace 25h (cooldown 24h), SÍ puede reclamar
set local request.jwt.claims = '{"sub":"aaaaaaa2-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (public.claim_faucet() ->> 'balance')::bigint,
  public.config_int('faucet_amount'),
  'Tras expirar el cooldown se puede volver a reclamar'
);

-- 7. Un usuario NO puede escribir su wallet directamente (permiso revocado)
prepare escribir_wallet as
  update public.wallets set balance = 999999 where user_id = 'aaaaaaa2-0000-0000-0000-000000000002';
select throws_ok('escribir_wallet', '42501', null, 'UPDATE directo a wallets prohibido');

-- 8. RLS: el usuario 2 NO ve la wallet del usuario 1
select is(
  (select count(*)::int from public.wallets where user_id = 'aaaaaaa1-0000-0000-0000-000000000001'),
  0,
  'RLS oculta las wallets ajenas'
);

select * from finish();
rollback;
