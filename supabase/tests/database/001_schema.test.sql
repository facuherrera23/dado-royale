-- Tests de la Fase 1: esquema, RLS, trigger de alta y ledger inmutable.
-- Se ejecutan con: npx supabase test db
begin;

select plan(8);

-- -------------------------------------------------------------
-- 1. RLS activado en todas las tablas públicas
-- -------------------------------------------------------------
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0,
  'Todas las tablas públicas tienen RLS activado'
);

-- -------------------------------------------------------------
-- 2. Trigger de alta: crear usuario => perfil + wallet con saldo 0
-- -------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('11111111-1111-1111-1111-111111111111', 'alice@test.dev', '{"username":"alice"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('22222222-2222-2222-2222-222222222222', 'bob@test.dev', '{}', 'authenticated', 'authenticated', now(), now(), now());

select ok(
  exists(select 1 from public.profiles where id = '11111111-1111-1111-1111-111111111111' and username = 'alice'),
  'El trigger crea el perfil con username del metadata'
);
select is(
  (select username from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'jugador_22222222',
  'Sin username en metadata se genera uno por defecto'
);
select ok(
  exists(select 1 from public.wallets where user_id = '11111111-1111-1111-1111-111111111111' and balance = 0),
  'El trigger crea la wallet con saldo 0'
);

-- -------------------------------------------------------------
-- 3. El saldo no puede ser negativo
-- -------------------------------------------------------------
prepare update_negativo as
  update public.wallets set balance = -1 where user_id = '11111111-1111-1111-1111-111111111111';
select throws_ok(
  'update_negativo',
  '23514',
  null,
  'La wallet rechaza saldos negativos CHECK(balance >= 0)'
);

-- -------------------------------------------------------------
-- 4. Ledger inmutable: UPDATE y DELETE están prohibidos
-- -------------------------------------------------------------
insert into public.ledger (user_id, type, amount, balance_after, idempotency_key)
values ('11111111-1111-1111-1111-111111111111', 'faucet', 1000, 1000, 'test-faucet-1');

prepare ledger_update as update public.ledger set amount = 5 where idempotency_key = 'test-faucet-1';
select throws_ok('ledger_update', null, 'El ledger es inmutable: no se permiten UPDATE ni DELETE', 'UPDATE al ledger prohibido');

prepare ledger_delete as delete from public.ledger where idempotency_key = 'test-faucet-1';
select throws_ok('ledger_delete', null, 'El ledger es inmutable: no se permiten UPDATE ni DELETE', 'DELETE al ledger prohibido');

-- -------------------------------------------------------------
-- 5. Idempotencia: misma clave no duplica movimientos
-- -------------------------------------------------------------
prepare ledger_duplicado as
  insert into public.ledger (user_id, type, amount, balance_after, idempotency_key)
  values ('11111111-1111-1111-1111-111111111111', 'faucet', 1000, 1000, 'test-faucet-1');
select throws_ok('ledger_duplicado', '23505', null, 'Idempotency_key duplicada es rechazada');

select * from finish();
rollback;
