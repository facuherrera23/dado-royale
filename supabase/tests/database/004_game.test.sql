-- Tests de la Fase 5: motor de juego (start_round, roll_round, cancel_round).
begin;
select plan(15);

-- Fixture: 4 usuarios con 100 fichas
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('ccccccc1-0000-0000-0000-000000000001', 'g1@test.dev', '{"username":"jug1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('ccccccc2-0000-0000-0000-000000000002', 'g2@test.dev', '{"username":"jug2"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('ccccccc3-0000-0000-0000-000000000003', 'g3@test.dev', '{"username":"jug3"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('ccccccc4-0000-0000-0000-000000000004', 'g4@test.dev', '{"username":"jug4"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 100 where user_id::text like 'ccccccc%';

-- Sentados directamente (fixture, no pasa por la RPC para aislar el test)
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('ccccccc1-0000-0000-0000-000000000001'::uuid), ('ccccccc2-0000-0000-0000-000000000002'::uuid)) as u(x)
where t.name = 'Mesa Oro';
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('ccccccc3-0000-0000-0000-000000000003'::uuid), ('ccccccc4-0000-0000-0000-000000000004'::uuid)) as u(x)
where t.name = 'Mesa Bronce';

-- =============================================================
-- PARTIDA 1: Mesa Oro (apuesta 100, pozo 200, comisión 4% = 8)
-- =============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"ccccccc1-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. start_round: pozo 200 y devuelve round_id
select is(
  (public.start_round((select id from public.tables where name = 'Mesa Oro')) ->> 'pot')::bigint,
  200::bigint,
  'start_round bloquea el pozo (2 × 100)'
);

-- 2-4. Apuestas bloqueadas: saldos a 0, dos bet_lock de -100 y mesa en partida
-- (las aserciones se hacen como superusuario para sortear RLS)
reset role;
select is((select balance from public.wallets where user_id = 'ccccccc1-0000-0000-0000-000000000001'),
  0::bigint, 'La apuesta se descuenta del saldo de jug1');
select is(
  (select count(*)::int from public.ledger where type = 'bet_lock' and amount = -100),
  2,
  'Se registran 2 movimientos bet_lock de -100'
);
select is((select status from public.tables where name = 'Mesa Oro'), 'in_round'::public.table_status,
  'La mesa pasa a in_round');

-- 5. Un no-participante no puede lanzar dados
reset role;
create temp table gid as
  select id from public.rounds
   where table_id = (select id from public.tables where name = 'Mesa Oro');
grant select on pg_temp.gid to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"ccccccc3-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok(
  $$select public.roll_round((select id from gid))$$,
  'P0014', null,
  'roll_round rechaza a quien no participa'
);

-- Ambos lanzan; repetimos rondas de tiros (idempotente) para absorber desempates.
-- roll_round es seguro tras el cierre: devuelve el estado sin efectos.
set local request.jwt.claims = '{"sub":"ccccccc1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from gid)) as r1;
set local request.jwt.claims = '{"sub":"ccccccc2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from gid)) as r2;
set local request.jwt.claims = '{"sub":"ccccccc1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from gid)) as r3;
set local request.jwt.claims = '{"sub":"ccccccc2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from gid)) as r4;
set local request.jwt.claims = '{"sub":"ccccccc1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from gid)) as r5;
set local request.jwt.claims = '{"sub":"ccccccc2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from gid)) as r6;
set local request.jwt.claims = '{"sub":"ccccccc1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.roll_round((select id from gid)) as r7;
set local request.jwt.claims = '{"sub":"ccccccc2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.roll_round((select id from gid)) as r8;

reset role;

select ok(
  (select bool_and(dice1 between 1 and 6 and dice2 between 1 and 6 and total between 2 and 12)
     from public.round_players where round_id = (select id from gid)),
  'Todos los dados caen entre 1 y 6 (rejection sampling sin sesgo)'
);
select ok(
  (select status in ('finished','cancelled') from public.rounds where id = (select id from gid)),
  'La ronda termina (finished o cancelled tras desempates)'
);

-- 8. EL LEDGER CUADRA: suma de movimientos de la ronda = 0
select is(
  (select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from gid)),
  0::bigint,
  'Los movimientos de la ronda cuadran a 0'
);

-- 9. Si hubo ganador: comisión = floor(200*4%) = 8 y payout = 192
select is(
  (select (case when r.status = 'cancelled'
               then (select count(*) from public.ledger where round_id = r.id and type = 'refund')
               else (select r2.house_fee + l.amount from public.rounds r2 join public.ledger l on l.round_id = r2.id and l.type = 'payout' where r2.id = r.id)
          end)::bigint
     from public.rounds r where r.id = (select id from gid)),
  (select (case when status = 'cancelled' then 2 else 200 end)::bigint from public.rounds where id = (select id from gid)),
  'finished: comisión 8 + premio 192 = pozo 200 (o refund completo si se agotaron desempates)'
);

-- 10. La casa cobra exactamente la comisión (si finished)
reset role;
select is(
  (select balance from public.house_account where id = true),
  (select (case when status = 'finished' then 8 else 0 end)::bigint from public.rounds where id = (select id from gid)),
  'house_account recibe solo la comisión del 4%'
);

-- 11. Segunda llamada a roll_round sobre ronda cerrada: idempotente
set local role authenticated;
set local request.jwt.claims = '{"sub":"ccccccc1-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.roll_round((select id from gid))$$,
  'roll_round sobre ronda cerrada es idempotente (no duplica pagos)');
reset role;
select is(
  (select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from gid)),
  0::bigint,
  'El ledger sigue cuadrando tras llamadas repetidas'
);

-- =============================================================
-- PARTIDA 2: Mesa Bronce — cancelación por timeout con refund
-- =============================================================
set local request.jwt.claims = '{"sub":"ccccccc3-0000-0000-0000-000000000003","role":"authenticated"}';
select public.start_round((select id from public.tables where name = 'Mesa Bronce')) as start_bronce;
reset role;
create temp table gid2 as select id from public.rounds where status = 'in_progress';
grant select on pg_temp.gid2 to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"ccccccc4-0000-0000-0000-000000000004","role":"authenticated"}';

-- 12. Cancelar antes del timeout => rechazado
select throws_ok($$select public.cancel_round((select id from gid2))$$,
  'P0015', null, 'cancel_round rechaza cancelar antes del timeout');

-- 13-14. Ronda envejecida => refund completo y saldos restaurados
reset role;
update public.rounds set created_at = now() - interval '1 hour' where id = (select id from gid2);
set local role authenticated;
set local request.jwt.claims = '{"sub":"ccccccc4-0000-0000-0000-000000000004","role":"authenticated"}';
select is(public.cancel_round((select id from gid2)) ->> 'status', 'cancelled',
  'cancel_round reembolsa una ronda atascada');
reset role;
select is((select balance from public.wallets where user_id = 'ccccccc3-0000-0000-0000-000000000003'),
  '100'::bigint, 'El reembolso devuelve la apuesta íntegra (sin comisión)');

select * from finish();
rollback;
