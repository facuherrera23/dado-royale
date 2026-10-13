-- Tests Fase 15: Guerra y RPS.
begin;
select plan(9);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('aaaa0001-0000-0000-0000-000000000001', 'w1@test.dev', '{"username":"war1g"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('aaaa0002-0000-0000-0000-000000000002', 'w2@test.dev', '{"username":"war2g"}', 'authenticated', 'authenticated', now(), now(), now());
update public.profiles set kyc_verified = true where username like 'war%';
update public.wallets set balance = 500;

-- Sentados en Guerra Bronce y RPS Bronce
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('aaaa0001-0000-0000-0000-000000000001'::uuid), ('aaaa0002-0000-0000-0000-000000000002'::uuid)) as u(x)
where t.name in ('Guerra Bronce','RPS Bronce');

-- ---------- WAR ----------
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaa0001-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (public.start_round((select id from public.tables where name = 'Guerra Bronce')) ->> 'pot')::bigint,
  20::bigint,
  'War: pozo = 2 × 10 fichas'
);

reset role;
create temp table wr as select id from public.rounds where status='in_progress' limit 1;
grant select on pg_temp.wr to authenticated;

-- Ambos roban carta (idempotente en bucle para desempates)
create temp table wr_rolls as select 1;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaa0001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from wr)) as w1a;
set local request.jwt.claims = '{"sub":"aaaa0002-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from wr)) as w2a;
set local request.jwt.claims = '{"sub":"aaaa0001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from wr)) as w1b;
set local request.jwt.claims = '{"sub":"aaaa0002-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from wr)) as w2b;
set local request.jwt.claims = '{"sub":"aaaa0001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from wr)) as w1c;
set local request.jwt.claims = '{"sub":"aaaa0002-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from wr)) as w2c;
set local request.jwt.claims = '{"sub":"aaaa0001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from wr)) as w1d;
set local request.jwt.claims = '{"sub":"aaaa0002-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from wr)) as w2d;

reset role;
select ok(
  (select bool_and(card1 between 1 and 52) from public.round_players where round_id = (select id from wr)),
  'War: cartas válidas 1..52'
);
select ok(
  (select status in ('finished','cancelled') from public.rounds where id = (select id from wr)),
  'War: la ronda termina'
);
select is(
  (select coalesce(sum(amount),0)::bigint from public.ledger where round_id = (select id from wr)),
  0::bigint,
  'War: ledger cuadra a 0'
);

-- ---------- RPS ----------
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('aaaa0001-0000-0000-0000-000000000001'::uuid), ('aaaa0002-0000-0000-0000-000000000002'::uuid)) as u(x)
where t.name = 'RPS Bronce'
on conflict (table_id, user_id) do update set status = 'seated';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaa0001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'RPS Bronce')) as rpsstart;

create temp table rr as select id from public.rounds where status = 'in_progress' order by created_at desc limit 1;
grant select on pg_temp.rr to authenticated;

-- Las elecciones no son visibles públicamente
select throws_ok($$select round_id from public.round_rps_choices limit 1$$,
  '42501', null, 'RPS: las elecciones son inaccesibles desde la API');

-- Elección inválida
select throws_ok($$select public.rps_play((select id from rr), 5::smallint)$$,
  'P0019', null, 'RPS: elección inválida rechazada');

-- Juego: piedra vs tijeras => gana piedra
select public.rps_play((select id from rr), 1::smallint) as c1;
set local request.jwt.claims = '{"sub":"aaaa0002-0000-0000-0000-000000000002","role":"authenticated"}';
select public.rps_play((select id from rr), 3::smallint) as c2;

reset role;
select is(
  (select winner_id::text from public.rounds where id = (select id from rr)),
  'aaaa0001-0000-0000-0000-000000000001',
  'RPS: piedra gana a tijeras (winner correcto)'
);
select is(
  (select coalesce(sum(amount),0)::bigint from public.ledger where round_id = (select id from rr)),
  0::bigint,
  'RPS: ledger cuadra a 0'
);
select ok(
  (select count(*) = 0 from public.round_rps_choices where round_id = (select id from rr)),
  'RPS: las elecciones se limpian al terminar'
);

select * from finish();
rollback;
