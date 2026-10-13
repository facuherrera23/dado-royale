-- Tests de la Fase 14: estadísticas personales por juego.
begin;
select plan(4);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('f0000001-0000-0000-0000-000000000001', 's1@test.dev', '{"username":"stats1"}', 'authenticated', 'authenticated', now(), now(), now());

-- 1 ronda de dados ganada (is_winner) y 1 de blackjack perdida (result=loss)
insert into public.rounds (table_id, status, pot)
  select id, 'finished', 100 from public.tables where game = 'dice' limit 1;
insert into public.round_players (round_id, user_id, bet_amount, is_winner)
select r.id, 'f0000001-0000-0000-0000-000000000001', 50, true
  from public.rounds r join public.tables on tables.id = r.table_id where tables.game = 'dice';

insert into public.rounds (table_id, status, pot)
  select id, 'finished', 100 from public.tables where game = 'blackjack' limit 1;
insert into public.round_players (round_id, user_id, hand_no, bet_amount, result)
select r.id, 'f0000001-0000-0000-0000-000000000001', 1, 50, 'loss'
  from public.rounds r join public.tables on tables.id = r.table_id where tables.game = 'blackjack';

-- Movimientos: bet_lock de 50 en cada juego + payout 96 en dados
insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
select 'f0000001-0000-0000-0000-000000000001', 'bet_lock', -50, 0, r.id, 'seed-bl-' || r.id
  from public.rounds r;
insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
select 'f0000001-0000-0000-0000-000000000001', 'payout', 96, 96, r.id, 'seed-py-' || r.id
  from public.rounds r join public.tables t on t.id = r.table_id where t.game = 'dice';

set local role authenticated;
set local request.jwt.claims = '{"sub":"f0000001-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1-4. Estadísticas por juego
select is(
  (select g ->> 'won' from jsonb_array_elements(public.get_my_stats()) g
    where g ->> 'game' = 'dice'),
  '1', 'Dados: 1 victoria');
select is(
  (select g ->> 'net' from jsonb_array_elements(public.get_my_stats()) g
    where g ->> 'game' = 'dice'),
  '46', 'Dados: neto +46 (-50 + 96)');
select is(
  (select g ->> 'lost' from jsonb_array_elements(public.get_my_stats()) g
    where g ->> 'game' = 'blackjack'),
  '1', 'Blackjack: 1 derrota');
select is(
  (select g ->> 'net' from jsonb_array_elements(public.get_my_stats()) g
    where g ->> 'game' = 'blackjack'),
  '-50', 'Blackjack: neto -50');

select * from finish();
rollback;
