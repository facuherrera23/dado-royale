-- Tests de la Fase 12: ranking filtrado por juego.
begin;
select plan(3);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('d0000001-0000-0000-0000-000000000001', 'rk@test.dev', '{"username":"rankeado"}', 'authenticated', 'authenticated', now(), now(), now());

-- Una ronda de dados y otra de blackjack ganadas por el mismo jugador
insert into public.rounds (table_id, status, pot)
  select id, 'finished', 100 from public.tables where game = 'dice' limit 1;
insert into public.rounds (table_id, status, pot)
  select id, 'finished', 100 from public.tables where game = 'blackjack' limit 1;

insert into public.round_players (round_id, user_id, bet_amount, is_winner)
select r.id, 'd0000001-0000-0000-0000-000000000001', 50, true
  from public.rounds r join public.tables t on t.id = r.table_id where t.game = 'dice';
insert into public.round_players (round_id, user_id, hand_no, bet_amount, result)
select r.id, 'd0000001-0000-0000-0000-000000000001', 1, 50, 'win'
  from public.rounds r join public.tables t on t.id = r.table_id where t.game = 'blackjack';

insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
select 'd0000001-0000-0000-0000-000000000001', 'payout', 96, 96, r.id, 'seed-payout-' || r.id
  from public.rounds r;

-- 1. Sin filtro: una victoria por cada juego
select is(
  (select rounds_won from public.get_leaderboard(10, null) where username = 'rankeado'),
  2::bigint,
  'Ranking global: 2 rondas ganadas (dados + blackjack)'
);

-- 2. Filtro dados: solo 1
select is(
  (select rounds_won from public.get_leaderboard(10, 'dice') where username = 'rankeado'),
  1::bigint,
  'Filtrando por dados: 1 ronda'
);

-- 3. Filtro blackjack: solo 1 y total = 96
select is(
  (select total_won from public.get_leaderboard(10, 'blackjack') where username = 'rankeado'),
  96::bigint,
  'Filtrando por blackjack: total ganado 96'
);

select * from finish();
rollback;
