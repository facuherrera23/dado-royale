-- Tests de la Fase 11: doblar, separar, seguro y limpieza por cron.
begin;
select plan(15);

-- Fixture: un jugador rico solo en una mesa de blackjack (1 jugador basta)
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('c0010001-0000-0000-0000-000000000001', 'x1@test.dev', '{"username":"blackx1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('c0010002-0000-0000-0000-000000000002', 'x2@test.dev', '{"username":"blackx2"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 5000 where user_id::text like 'c0010%'; update public.profiles set kyc_verified = true where username like 'blackx%';
insert into public.table_players (table_id, user_id, status, pending_bet)
select t.id, 'c0010001-0000-0000-0000-000000000001', 'seated', 50
  from public.tables t where t.name = 'Blackjack Bronce';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Blackjack Bronce')) as r0;

reset role;
create temp table xr as select id from public.rounds where status = 'in_progress';
grant select on pg_temp.xr to authenticated;

-- ------------------------------------------------------------
-- 1-3. DOBLAR: apuesta x2, una carta y plantarse
-- ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.bj_action((select id from xr), 'double') as dbl;

reset role;
select is(
  (select bet_amount from public.round_players where round_id = (select id from xr)),
  100::bigint, 'Doblar duplica la apuesta (50 -> 100)'
);
select ok(
  (select cardinality(cards) = 3 and stood from public.round_players where round_id = (select id from xr)),
  'Doblar añade exactamente una carta y planta la mano'
);
select is(
  (select status::text from public.rounds where id = (select id from xr)),
  'finished',
  'Sin más manos abiertas la ronda se liquida (jugador único)'
);
select is(
  (select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from xr)),
  0::bigint,
  'Ledger cuadra a 0 tras doblar y liquidar'
);

-- ------------------------------------------------------------
-- 5. Doblar con más de dos cartas está prohibido (siguiente ronda)
-- ------------------------------------------------------------
reset role;
update public.table_players set pending_bet = 50 where user_id = 'c0010001-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Blackjack Bronce')) as r1;
reset role;
create temp table xr2 as select id from public.rounds where status = 'in_progress'
  order by created_at desc limit 1;
grant select on pg_temp.xr2 to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
-- Forzamos determinísticamente una tercera carta (como superusuario)
reset role;
update public.round_players
   set cards = cards || (select min(c)::smallint from generate_series(1,52) g(c)
                          where c::smallint <> all (cards))
 where round_id = (select id from xr2);
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.bj_action((select id from xr2), 'double')$$,
  'P0023', null, 'No se puede doblar tras pedir carta');

-- ------------------------------------------------------------
-- 6-8. SEGURO: solo con as a la vista; natural de la banca paga 2:1
-- ------------------------------------------------------------
reset role;
-- Forzamos las cartas del dealer (como superusuario; la API nunca lo permite)
update public.rounds set dealer_cards = array[13::smallint, 38::smallint] where id = (select id from xr2); delete from public.round_dealer_holes where round_id = (select id from xr2); -- A y K: natural
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
-- Ya pidió carta antes: seguro solo se puede antes de jugar la mano (P0020)? Lo probamos:
select throws_ok($$select public.bj_action((select id from xr2), 'insurance')$$,
  null, null, 'Seguro tras haber pedido carta se controla (no explota)');
select is(
  (select insurance from public.round_players where round_id = (select id from xr2) and hand_no = 1),
  null::bigint,
  'El seguro no se registró tras haber actuado'
);

-- liquidamos para cerrar la ronda
select public.bj_action((select id from xr2), 'stand') as fin2;
reset role;

-- Seguro ganador: nueva ronda, seguro ANTES de actuar, dealer con natural
update public.table_players set pending_bet = 50 where user_id = 'c0010001-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Blackjack Bronce')) as r2;
reset role;
create temp table xr3 as select id from public.rounds where status = 'in_progress' order by created_at desc limit 1;
grant select on pg_temp.xr3 to authenticated;
update public.rounds set dealer_cards = array[13::smallint, 38::smallint] where id = (select id from xr3); delete from public.round_dealer_holes where round_id = (select id from xr3);

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (public.bj_action((select id from xr3), 'insurance') ->> 'status'),
  'insured',
  'Seguro aceptado: la banca muestra un As'
);
reset role;
select is(
  (select insurance from public.round_players where round_id = (select id from xr3) and hand_no = 1),
  25::bigint, 'El seguro es la mitad de la apuesta (50/2 = 25)'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.bj_action((select id from xr3), 'stand') as fin3;
reset role;
-- Seguro paga 2:1 => devuelve 3×25 = 75; el jugador pierde la mano (no tiene natural)
select ok(
  exists(select 1 from public.ledger
          where round_id = (select id from xr3) and type = 'payout'
            and user_id = 'c0010001-0000-0000-0000-000000000001' and amount = 75),
  'El seguro pagó 2:1 (75 = 3 × 25)'
);
select is(
  (select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from xr3)),
  0::bigint,
  'Ledger cuadra a 0 con seguro'
);

-- ------------------------------------------------------------
-- 10-11. SEPARAR un par: dos manos, dos apuestas
-- ------------------------------------------------------------
update public.table_players set pending_bet = 50 where user_id = 'c0010001-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Blackjack Bronce')) as r3;
reset role;
create temp table xr4 as select id from public.rounds where status = 'in_progress' order by created_at desc limit 1;
grant select on pg_temp.xr4 to authenticated;

-- Forzamos un par de doses (cartas 27 y 40: mismo valor)
reset role;
update public.round_players set cards = '{}'::smallint[] where round_id = (select id from xr4);
update public.rounds set dealer_cards = '{}'::smallint[] where id = (select id from xr4);
update public.round_players set cards = array[27::smallint, 40::smallint] where round_id = (select id from xr4);
update public.rounds set dealer_cards = array[1::smallint, 2::smallint] where id = (select id from xr4);

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select is((public.bj_action((select id from xr4), 'split') ->> 'status'), 'split',
  'Separar un par crea la segunda mano');
reset role;
select ok(
  (select count(*) = 2 and min(cardinality(cards)) = 2 from public.round_players
    where round_id = (select id from xr4)),
  'Tras separar: dos manos con dos cartas cada una'
);

-- 12. Cerrar ambas manos y el ledger sigue cuadrando
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.bj_action((select id from xr4), 'stand', 1::smallint) as s1;
select public.bj_action((select id from xr4), 'stand', 2::smallint) as s2;
reset role;
select is(
  (select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from xr4)),
  0::bigint,
  'Ledger cuadra a 0 tras separar y liquidar ambas manos'
);

-- 13. cancel_stale_rounds: cancela y reembolsa rondas viejas sin actividad
update public.table_players set pending_bet = 50 where user_id = 'c0010001-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0010001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Blackjack Bronce')) as r4;
reset role;
update public.rounds set created_at = now() - interval '1 hour' where status = 'in_progress';
select ok(public.cancel_stale_rounds() >= 1, 'cancel_stale_rounds cancela rondas atascadas');

select * from finish();
rollback;
