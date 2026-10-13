-- Tests de la Fase 4: join_table / leave_table
begin;
select plan(11);

-- Fixture: 3 usuarios con saldo (faucet simulado como superusuario)
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('bbbbbbb1-0000-0000-0000-000000000001', 't1@test.dev', '{"username":"uno_test"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('bbbbbbb2-0000-0000-0000-000000000002', 't2@test.dev', '{"username":"dos_test"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('bbbbbbb3-0000-0000-0000-000000000003', 't3@test.dev', '{"username":"tres_test"}', 'authenticated', 'authenticated', now(), now(), now());

update public.wallets set balance = 100 where user_id::text like 'bbbbbbb%';

-- Uno sin saldo: forzado en FASE de test (superusuario puede escribir wallet)
update public.wallets set balance = 0 where user_id = 'bbbbbbb3-0000-0000-0000-000000000003';

-- IDs de mesas
create temp table test_tables as
  select id, bet_amount, max_players from public.tables order by bet_amount limit 4;

set local role authenticated;

-- 1. Sin autenticar => rechazado
select throws_ok($$select public.join_table((select id from public.tables limit 1))$$,
  'P0001', 'No autenticado', 'join_table exige autenticación');

set local request.jwt.claims = '{"sub":"bbbbbbb1-0000-0000-0000-000000000001","role":"authenticated"}';

-- 2. Unirse a la mesa Bronce: éxito
select is(
  public.join_table((select id from public.tables where name = 'Mesa Bronce')) ->> 'status',
  'seated',
  'join_table sienta al jugador'
);

-- 3. Unirse de nuevo: idempotente, no duplica fila
select lives_ok($$select public.join_table((select id from public.tables where name = 'Mesa Bronce'))$$,
  'join_table repetido es idempotente');

-- 4. Rate limit: salir justo después de sentarse => rechazado
select throws_ok(
  $$select public.leave_table((select id from public.tables where name = 'Mesa Bronce'))$$,
  'P0006', null,
  'leave_table inmediato choca con el rate limit'
);

-- 5. "Envejecemos" la acción (superusuario) y salimos con éxito
reset role;
update public.table_players set last_action_at = now() - interval '1 minute'
 where user_id = 'bbbbbbb1-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbb1-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  public.leave_table((select id from public.tables where name = 'Mesa Bronce')) ->> 'status',
  'left',
  'leave_table funciona tras el cooldown'
);

-- 6. Saldo insuficiente: usuario 3 (0 fichas) no puede sentarse en Diamante (500)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbb3-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$select public.join_table((select id from public.tables where name = 'Mesa Diamante'))$$,
  'P0009', null,
  'join_table rechaza saldo insuficiente'
);

-- 7. Aforo: Plata con aforo 2 se llena con u1 y u2; u3 es rechazado
reset role;
update public.tables set max_players = 2 where name = 'Mesa Plata';
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbb1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.join_table((select id from public.tables where name = 'Mesa Plata'));
set local request.jwt.claims = '{"sub":"bbbbbbb2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.join_table((select id from public.tables where name = 'Mesa Plata'));

set local request.jwt.claims = '{"sub":"bbbbbbb3-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$select public.join_table((select id from public.tables where name = 'Mesa Plata'))$$,
  'P0008', null,
  'join_table rechaza mesa llena'
);

-- 8. Una sola mesa: usuario 1 sentado en Plata no puede entrar en Bronce
set local request.jwt.claims = '{"sub":"bbbbbbb1-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$select public.join_table((select id from public.tables where name = 'Mesa Bronce'))$$,
  'P0007', null,
  'join_table rechaza estar sentado en dos mesas'
);

-- 9. RLS: table_players es de solo lectura para la API (permiso revocado)
prepare sentarse_directo as
  insert into public.table_players (table_id, user_id) values
    ((select id from public.tables where name = 'Mesa Oro'), 'bbbbbbb1-0000-0000-0000-000000000001');
select throws_ok('sentarse_directo', '42501', null, 'INSERT directo a table_players prohibido');

-- 10-11. Saldo intacto: sentarse no mueve fichas ni escribe ledger
select is((select balance from public.wallets where user_id = 'bbbbbbb1-0000-0000-0000-000000000001'),
  100::bigint, 'Sentarse no descuenta fichas');
select is((select count(*)::int from public.ledger where user_id = 'bbbbbbb1-0000-0000-0000-000000000001'),
  0, 'Sentarse no escribe en el ledger');

select * from finish();
rollback;
