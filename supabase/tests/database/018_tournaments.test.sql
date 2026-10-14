-- Tests Fase 19: torneos (inscripción, premios, reembolso).
begin;
select plan(9);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('dada0001-0000-0000-0000-000000000001', 'ta@test.dev', '{"username":"tournA"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('dada0002-0000-0000-0000-000000000002', 'tb@test.dev', '{"username":"tournB"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('dada0003-0000-0000-0000-000000000003', 'tc@test.dev', '{"username":"tournC"}', 'authenticated', 'authenticated', now(), now(), now());
update public.profiles set kyc_verified = true where username like 'tourn%';
update public.wallets set balance = 1000 where user_id::text like 'dada%';

-- Torneo de dados: buy-in 100, ventana activa
insert into public.tournaments (name, game, buy_in, starts_at, ends_at, min_players)
values ('Torneo Test', 'dice', 100, now() - interval '1 day', now() + interval '1 day', 3);
create temp table tt as select id from public.tournaments where name = 'Torneo Test';
grant select on pg_temp.tt to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"dada0001-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. Inscripción: descuenta 100 del saldo y escribe buy_in
select is(
  (public.register_tournament((select id from tt)) ->> 'status'), 'registered',
  'Inscripción al torneo funciona');
reset role;
select is((select balance from public.wallets where user_id = 'dada0001-0000-0000-0000-000000000001'),
  900::bigint, 'El buy-in se descuenta');
select ok(
  exists(select 1 from public.ledger where tournament_id = (select id from tt)
          and type = 'buy_in' and amount = -100),
  'buy_in registrado con espejo a la casa'
);

-- 2. Segunda inscripción idempotente; 3 jugadores entran al torneo
set local role authenticated;
set local request.jwt.claims = '{"sub":"dada0001-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.register_tournament((select id from tt))$$, 'Doble inscripción idempotente');

set local request.jwt.claims = '{"sub":"dada0002-0000-0000-0000-000000000002","role":"authenticated"}';
select public.register_tournament((select id from tt)) as rB;
set local request.jwt.claims = '{"sub":"dada0003-0000-0000-0000-000000000003","role":"authenticated"}';
select public.register_tournament((select id from tt)) as rC;

-- 3. No se puede finalizar en caliente
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dada0001-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.finalize_tournament((select id from tt))$$,
  'P0062', null, 'finalize antes del cierre es rechazado');

-- 4. Volvemos el torneo "acabado" y jugamos: A gana una ronda, B pierde, C no juega
reset role;
-- Simulamos resultados: A +96 en dados, B -10 en dados
insert into public.rounds (table_id, status, pot)
  select id, 'finished', 100 from public.tables where game = 'dice' limit 1;
insert into public.round_players (round_id, user_id, bet_amount, is_winner)
select r.id, 'dada0001-0000-0000-0000-000000000001', 10, true
  from public.rounds r where status = 'finished' limit 1;
insert into public.round_players (round_id, user_id, bet_amount, is_winner)
select r.id, 'dada0002-0000-0000-0000-000000000002', 10, false
  from public.rounds r where status = 'finished' limit 1;
insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
select 'dada0001-0000-0000-0000-000000000001', 'payout', 96, r.id, 'seed-tp-' || r.id
  from public.rounds r order by r.created_at desc limit 1;
insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
select 'dada0001-0000-0000-0000-000000000001', 'bet_lock', -10, r.id, 'seed-tb-' || r.id
  from public.rounds r order by r.created_at desc limit 1;
insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
select 'dada0002-0000-0000-0000-000000000002', 'bet_lock', -10, r.id, 'seed-tc-' || r.id
  from public.rounds r order by r.created_at desc limit 1;

update public.tournaments set ends_at = now() - interval '10 minutes' where id = (select id from tt);

set local role authenticated;
set local request.jwt.claims = '{"sub":"dada0001-0000-0000-0000-000000000001","role":"authenticated"}';

-- Top3 con 3 inscritos y buy-in 100: pozo 300; fee 4% = 12; neto 288 -> 50% 144 / 30% 86 / 20% 57
select is(
  (public.finalize_tournament((select id from tt)) ->> 'status'), 'finished',
  'finalize reparte premios');

reset role;
select is((select balance from public.wallets where user_id = 'dada0001-0000-0000-0000-000000000001'),
  (900 + 144)::bigint, 'El 1º gana 50% del pozo neto (144)');
select is((select balance from public.wallets where user_id = 'dada0002-0000-0000-0000-000000000002'),
  (900 + 86)::bigint, 'El 2º gana 30% (86)');

-- 5. Doble finalize: idempotente
set local role authenticated;
set local request.jwt.claims = '{"sub":"dada0001-0000-0000-0000-000000000001","role":"authenticated"}';
select is((public.finalize_tournament((select id from tt)) ->> 'status'), 'finished',
  'Doble finalize es idempotente');

select * from finish();
rollback;
