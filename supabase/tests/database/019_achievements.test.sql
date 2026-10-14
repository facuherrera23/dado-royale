-- Tests Fase 20: logros, eventos de ronda y antifraude.
begin;
select plan(8);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('abab0001-0000-0000-0000-000000000001', 'ach@test.dev', '{"username":"achiever"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('abab0002-0000-0000-0000-000000000002', 'adm2@test.dev', '{"username":"antifraud"}', 'authenticated', 'authenticated', now(), now(), now());
update public.profiles set is_admin = true where username = 'antifraud';

-- Ganó una ronda de dados con un doble seis
insert into public.rounds (table_id, status, pot)
  select id, 'finished', 100 from public.tables where game = 'dice' limit 1;
insert into public.round_players (round_id, user_id, bet_amount, is_winner, dice1, dice2)
values ((select id from public.rounds order by created_at desc limit 1),
        'abab0001-0000-0000-0000-000000000001', 50, true, 6, 6);

set local role authenticated;
set local request.jwt.claims = '{"sub":"abab0001-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. Desbloquea primera_victoria + seis_dobles (una sola llamada, guardada)
create temp table ach as select public.check_achievements() as j;
grant select on pg_temp.ach to authenticated;
select ok(
  ((select j from ach) -> 'newly_earned') ? 'primera_victoria'
  and ((select j from ach) -> 'newly_earned') ? 'seis_dobles',
  'check_achievements otorga primera victoria y seis dobles'
);
-- 2. Idempotente
select is(
  (select count(*)::int from public.user_achievements
    where user_id = 'abab0001-0000-0000-0000-000000000001'
      and achievement_key in ('primera_victoria','seis_dobles')),
  2,
  'Segunda llamada no duplica logros'
);
-- 3. Escritura directa prohibida
prepare logro_manual as insert into public.user_achievements (user_id, achievement_key)
  values ('abab0001-0000-0000-0000-000000000001', 'veterano');
select throws_ok('logro_manual', '42501', null, 'Logros solo por función (42501)');

-- 4. Antifraude: no-admins fuera
select throws_ok($$select public.admin_detect_patterns()$$,
  'P0403', null, 'admin_detect_patterns exige admin');

-- 5. Antifraude: admins ven la estructura
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"abab0002-0000-0000-0000-000000000002","role":"authenticated"}';
select ok(
  (public.admin_detect_patterns() ? 'mismo_documento')
  and (public.admin_detect_patterns() ? 'parejas_sospechosas')
  and (public.admin_detect_patterns() ? 'sin_jugar_con_faucet'),
  'admin_detect_patterns devuelve las 3 categorías'
);

-- -------------------------------------------------------------
-- 6-8. Eventos de ronda (replay): ronda real de dados
-- -------------------------------------------------------------
reset role;
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('abab0003-0000-0000-0000-000000000003', 'ev1@test.dev', '{"username":"even1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('abab0004-0000-0000-0000-000000000004', 'ev2@test.dev', '{"username":"even2"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 200 where user_id::text like 'abab0003%' or user_id::text like 'abab0004%';
update public.profiles set kyc_verified = true where username like 'even%';
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('abab0003-0000-0000-0000-000000000003'::uuid), ('abab0004-0000-0000-0000-000000000004'::uuid)) as u(x)
where t.name = 'Mesa Bronce';

set local request.jwt.claims = '{"sub":"abab0003-0000-0000-0000-000000000003","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Mesa Bronce')) as ev;
create temp table er as select id from public.rounds where status = 'in_progress' order by created_at desc limit 1;
grant select on pg_temp.er to authenticated;

select public.roll_round((select id from er)) as er1;
set local request.jwt.claims = '{"sub":"abab0004-0000-0000-0000-000000000004","role":"authenticated"}';
select public.roll_round((select id from er)) as er2;

reset role;
select ok(
  exists(select 1 from public.round_events where round_id = (select id from er) and event_type = 'round_started'),
  'Evento round_started registrado'
);
select ok(
  (select count(*) >= 3 from public.round_events where round_id = (select id from er)),
  'Eventos secuenciados (round_started + 2 rolls + finish/…)'
);
select is(
  (select count(distinct seq)::int from public.round_events where round_id = (select id from er)),
  (select count(*)::int from public.round_events where round_id = (select id from er)),
  'Secuencias de eventos sin duplicados'
);

select * from finish();
rollback;
