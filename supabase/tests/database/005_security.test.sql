-- Prueba de ataque (criterio de aceptación): un usuario autenticado NO puede
-- alterar su saldo, los dados ni el ledger desde la API (consola del navegador).
begin;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('ddddddd1-0000-0000-0000-000000000001', 'hacker@test.dev', '{"username":"hack3r"}',
        'authenticated', 'authenticated', now(), now(), now());

-- Ronda de muestra para intentar manipular dados
insert into public.rounds (table_id, status, pot)
  select id, 'in_progress', 100 from public.tables limit 1;
create temp table hack_round as select id from public.rounds limit 1;
grant select on pg_temp.hack_round to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ddddddd1-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. No puede inflar su saldo
prepare robo_saldo as
  update public.wallets set balance = 1000000 where user_id = 'ddddddd1-0000-0000-0000-000000000001';
select throws_ok('robo_saldo', '42501', null, 'ATAQUE FALLIDO: update a wallets rechazado');

-- 2. No puede insertar un payout falso en el ledger
prepare pago_falso as
  insert into public.ledger (user_id, type, amount, balance_after)
  values ('ddddddd1-0000-0000-0000-000000000001', 'payout', 999999, 999999);
select throws_ok('pago_falso', '42501', null, 'ATAQUE FALLIDO: insert a ledger rechazado');

-- 3. No puede colocarse en la ronda
prepare colarse as
  insert into public.round_players (round_id, user_id, bet_amount)
  select id, 'ddddddd1-0000-0000-0000-000000000001', 999 from public.rounds limit 1;
select throws_ok('colarse', '42501', null, 'ATAQUE FALLIDO: insert a round_players rechazado');

-- 4. No puede elegir dados ganadores (ni siquiera en su propia fila)
prepare dados_trucados as
  update public.round_players set dice1 = 6, dice2 = 6;
select throws_ok('dados_trucados', '42501', null, 'ATAQUE FALLIDO: update a round_players rechazado');

-- 5. No puede vaciar la casa
prepare robar_casa as
  update public.house_account set balance = 0 where id = true;
select throws_ok('robar_casa', '42501', null, 'ATAQUE FALLIDO: update a house_account rechazado');

-- 6. No puede ver el balance de la casa (RLS)
select is(
  (select count(*)::int from public.house_account),
  0,
  'ATAQUE FALLIDO: la casa no es visible sin rol admin'
);

select * from finish();
rollback;
