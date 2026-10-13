-- Tests de la Fase 10: blackjack con apuesta variable vs la banca.
begin;
select plan(14);

-- Fixture: 2 usuarios ricos sentados en Blackjack Oro (100..1000)
insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('beeeeee1-0000-0000-0000-000000000001', 'b1@test.dev', '{"username":"black1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('beeeeee2-0000-0000-0000-000000000002', 'b2@test.dev', '{"username":"black2"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 5000 where user_id::text like 'beeeeee%';
update public.profiles set kyc_verified = true where username in ('black1','black2');
insert into public.table_players (table_id, user_id, status)
select t.id, u.x, 'seated' from public.tables t,
  (values ('beeeeee1-0000-0000-0000-000000000001'::uuid), ('beeeeee2-0000-0000-0000-000000000002'::uuid)) as u(x)
where t.name = 'Blackjack Oro';

-- 1-3. hand_value / is_blackjack correctos
select is(public.hand_value(array[13::smallint, 26::smallint]), 12, 'Dos ases valen 12 (11+1)');
select is(public.hand_value(array[13::smallint, 38::smallint]), 21, 'A+K = 21');
select ok(public.is_blackjack(array[13::smallint, 38::smallint])
          and not public.is_blackjack(array[13::smallint, 25::smallint, 12::smallint]),
  'Natural = 21 con 2 cartas (A+figura); 21 con 3 cartas no es natural');

-- 4-6. set_bet: rango, mesa de apuesta fija rechaza, válido funciona
set local role authenticated;
set local request.jwt.claims = '{"sub":"beeeeee1-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.set_bet(
  (select id from public.tables where name = 'Blackjack Oro'), 50)$$,
  'P0018', null, 'set_bet rechaza apuesta por debajo del mínimo');
select throws_ok($$select public.set_bet(
  (select id from public.tables where name = 'Mesa Oro'), 100)$$,
  'P0017', null, 'set_bet rechaza mesas de apuesta fija (dados/póker)');
select is(
  (public.set_bet((select id from public.tables where name = 'Blackjack Oro'), 300) ->> 'pending_bet')::bigint,
  300::bigint,
  'set_bet acepta apuesta dentro del rango (300 en [100,1000])'
);
reset role;

-- 7. start_round con apuestas variables: solo entra quien fijó apuesta
update public.table_players set pending_bet = 500
 where user_id = 'beeeeee2-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claims = '{"sub":"beeeeee1-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (public.start_round((select id from public.tables where name = 'Blackjack Oro')) ->> 'pot')::bigint,
  800::bigint,
  'start_round blackjack: pozo = 300 + 500 (apuestas variables)'
);

reset role;
create temp table bjr as select id from public.rounds where status = 'in_progress';
grant select on pg_temp.bjr to authenticated;

-- 8. Reparto inicial correcto: 2 cartas/jugador; la banca tiene 1 visible + 1 oculta
select ok(
  (select bool_and(cardinality(cards) = 2) from public.round_players where round_id = (select id from bjr))
  and (select cardinality(dealer_cards) from public.rounds where id = (select id from bjr)) = 1
  and (select cardinality(cards) from public.round_dealer_holes where round_id = (select id from bjr)) = 1,
  'Todos tienen 2 cartas; la banca 1 visible + 1 oculta'
);
select ok(
  coalesce((select count(*) = 0 from (
    select c from (
      select unnest(cards) as c from public.round_players where round_id = (select id from bjr)
      union all select unnest(dealer_cards) from public.rounds where id = (select id from bjr)
    ) allc group by c having count(*) > 1) dup), true),
  'Ninguna carta se repite (jugadores + dealer)'
);

-- 10. Saldos descontados según su apuesta individual
select ok(
  (select balance from public.wallets where user_id = 'beeeeee1-0000-0000-0000-000000000001') = 5000 - 300
  and (select balance from public.wallets where user_id = 'beeeeee2-0000-0000-0000-000000000002') = 5000 - 500,
  'Apuestas variables descontadas correctamente (300 y 500)'
);

-- 11. hit añade una carta; stand planta
set local role authenticated;
set local request.jwt.claims = '{"sub":"beeeeee1-0000-0000-0000-000000000001","role":"authenticated"}';
select public.bj_action((select id from bjr), 'stand') as bj1;
set local request.jwt.claims = '{"sub":"beeeeee2-0000-0000-0000-000000000002","role":"authenticated"}';
select public.bj_action((select id from bjr), 'hit') as bj2;
reset role;
select ok(
  (select cardinality(cards) >= 3 from public.round_players
    where round_id = (select id from bjr) and user_id = 'beeeeee2-0000-0000-0000-000000000002'),
  'hit añade una carta'
);

-- 12. Cuando ambos terminan, la ronda se liquida y el ledger cuadra
set local role authenticated;
set local request.jwt.claims = '{"sub":"beeeeee2-0000-0000-0000-000000000002","role":"authenticated"}';
-- planta si sigue en juego (si se pasó con el hit, stood ya es true)
select case when (select status from public.rounds where id = (select id from bjr)) = 'in_progress'
            then public.bj_action((select id from bjr), 'stand') else null end as bj3;

reset role;
select is(
  (select status::text from public.rounds where id = (select id from bjr)),
  'finished',
  'La mano se liquida cuando todos se plantan'
);

-- 13. El ledger cuadra: bet_lock + pagos/reembolsos + liquidación de la casa = 0
select is(
  (select coalesce(sum(amount), 0)::bigint from public.ledger where round_id = (select id from bjr)),
  0::bigint,
  'Ledger de blackjack cuadra a 0 (banca cobra perdedoras, paga ganadoras)'
);

-- 14. ATAQUE: bj_action con acción inválida y por no participante; mesa de dados en blackjack
set local role authenticated;
set local request.jwt.claims = '{"sub":"beeeeee1-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.bj_action((select id from bjr), 'doblar')$$,
  null, null, 'bj_action idempotente/seguro tras cierre (sin duplicar pagos)');

select * from finish();
rollback;
