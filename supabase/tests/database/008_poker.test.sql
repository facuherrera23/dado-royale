-- Tests de la Fase 9: póker de 2 cartas.
begin;
select plan(12);

-- Fixture: 2 usuarios ricos sentados en Póker Oro
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('fffffff1-0000-0000-0000-000000000001', 'p1@test.dev', '{"username":"poker1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('fffffff2-0000-0000-0000-000000000002', 'p2@test.dev', '{"username":"poker2"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 500 where user_id::text like 'fffffff%';
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('fffffff1-0000-0000-0000-000000000001'::uuid), ('fffffff2-0000-0000-0000-000000000002'::uuid)) as u(x)
where t.name = 'Póker Oro';

-- 1. Funciones internas de cartas: sin EXECUTE para authenticated
select is(
  (select count(*)::int from information_schema.routine_privileges
    where grantee = 'authenticated' and specific_schema = 'public'
      and routine_name in ('_uniform','draw_card','card_rank','hand_score')),
  0,
  'draw_card/hand_score no son llamables desde la API'
);

-- 2. hand_score: pareja gana a carta alta; y A de kicker gana a K
reset role;
select ok(public.hand_score(1::smallint, 40::smallint) > public.hand_score(13::smallint, 25::smallint),
  'Pareja de 2s (1,40) gana a A+K sin pareja (13,25)');
select ok(public.hand_score(13::smallint, 26::smallint) > public.hand_score(13::smallint, 25::smallint),
  'Pareja de ases (13,26) gana a A+K sin pareja (13,25)');

-- 3-4. Partida de póker: arranque bloquea pozo 200 y cartas válidas distintas
set local role authenticated;
set local request.jwt.claims = '{"sub":"fffffff1-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (public.start_round((select id from public.tables where name = 'Póker Oro')) ->> 'pot')::bigint,
  200::bigint,
  'start_round en mesa de póker bloquea el pozo'
);
reset role;
create temp table prnd as select id from public.rounds where status = 'in_progress';
grant select on pg_temp.prnd to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"fffffff1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play1;
set local request.jwt.claims = '{"sub":"fffffff2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play2;
-- rondas de re-juego por si hay desempates
set local request.jwt.claims = '{"sub":"fffffff1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play3;
set local request.jwt.claims = '{"sub":"fffffff2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play4;
set local request.jwt.claims = '{"sub":"fffffff1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play5;
set local request.jwt.claims = '{"sub":"fffffff2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play6;
set local request.jwt.claims = '{"sub":"fffffff1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play7;
set local request.jwt.claims = '{"sub":"fffffff2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from prnd)) as play8;

reset role;
-- 5. Todas las cartas repartidas son válidas y no hay duplicados en la ronda
select ok(
  (select bool_and(card1 between 1 and 52 and card2 between 1 and 52)
     from public.round_players where round_id = (select id from prnd)),
  'Cartas en rango 1..52'
);
select ok(
  coalesce((select count(*) = 0 from (
    select card from (
      select card1 as card from public.round_players where round_id = (select id from prnd) and card1 is not null
      union all
      select card2 from public.round_players where round_id = (select id from prnd) and card2 is not null
    ) c group by card having count(*) > 1
  ) dup), true),
  'No hay cartas repetidas (baraja única)'
);

-- 6-9. La ronda terminó, ledger cuadra, comisión 8 = floor(200*4%), house_account += 8
select ok((select status in ('finished','cancelled') from public.rounds where id = (select id from prnd)),
  'La ronda de póker termina (finished o cancelled)');
select is((select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from prnd)),
  0::bigint, 'Ledger de la ronda de póker cuadra a 0');
select is(
  (select (case when status='finished' then house_fee else 0 end)::bigint from public.rounds where id = (select id from prnd)),
  (select (case when status='finished' then 8 else 0 end)::bigint from public.rounds where id = (select id from prnd)),
  'Comisión 4% correcta si hubo ganador'
);

-- 10. draw_card no reparte cartas ya usadas: niega consecutive directo por usuario final
set local role authenticated;
set local request.jwt.claims = '{"sub":"fffffff1-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.draw_card(gen_random_uuid())$$,
  '42501', null, 'draw_card no es callable desde la API (denegada)');

-- 11-12. ATACAR las cartas: update directo prohibido y elegir pareja de ases también
prepare cartas_trucadas as update public.round_players set card1 = 13, card2 = 26;
select throws_ok('cartas_trucadas', '42501', null, 'ATAQUE FALLIDO: trucar cartas prohibido (42501)');
prepare meterse as insert into public.round_players (round_id, user_id, bet_amount)
  values ((select id from prnd), 'fffffff1-0000-0000-0000-000000000001', 1);
select throws_ok('meterse', '42501', null, 'ATAQUE FALLIDO: colarse en ronda prohibido (42501)');

select * from finish();
rollback;
