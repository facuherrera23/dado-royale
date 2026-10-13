-- Tests de la Fase 13: carta oculta real y edición de avatar.
begin;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('e0000001-0000-0000-0000-000000000001', 'h1@test.dev', '{"username":"avatar1"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 5000 where user_id = 'e0000001-0000-0000-0000-000000000001';
insert into public.table_players (table_id, user_id, status, pending_bet)
select id, 'e0000001-0000-0000-0000-000000000001', 'seated', 50
  from public.tables where name = 'Blackjack Bronce';

-- -------------------------------------------------------------
-- 1-2. La carta oculta NO es accesible desde la API
-- -------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0000001-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select round_id from public.round_dealer_holes$$,
  '42501', null, 'SELECT sobre round_dealer_holes denegado (42501)');

-- Contraste: en blackjack Bronze la ronda sí arranca y hay hueco en la tabla global
select public.start_round((select id from public.tables where name = 'Blackjack Bronce')) as hr;
reset role;
select is(
  (select count(*)::int from public.round_dealer_holes
    where round_id in (select id from public.rounds where status = 'in_progress')),
  1,
  'La banca tiene una carta oculta guardada fuera del alcance del cliente'
);

-- -------------------------------------------------------------
-- 3. Al liquidar, la carta oculta se revela (se funde y se borra)
-- -------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0000001-0000-0000-0000-000000000001","role":"authenticated"}';
select public.bj_action((select id from public.rounds where status = 'in_progress'), 'stand') as f1;
reset role;
select is(
  (select count(*)::int from public.round_dealer_holes
    where round_id in (select id from public.rounds where status = 'finished')),
  0,
  'Tras liquidar no queda ningún hueco (carta revelada)'
);

-- 4. Dealer terminó con todas sus cartas públicas (≥2)
select ok(
  (select cardinality(dealer_cards) >= 2 from public.rounds where status = 'finished'
    order by created_at desc limit 1),
  'dealer_cards contiene la carta oculta revelada al final'
);

-- -------------------------------------------------------------
-- 5-6. Avatar: el usuario puede cambiar el suyo pero no username
-- -------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"e0000001-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(
  $$update public.profiles set avatar_url = '🐯' where id = 'e0000001-0000-0000-0000-000000000001'$$,
  'El usuario puede editar su avatar'
);
select throws_ok(
  $$update public.profiles set username = 'hack' where id = 'e0000001-0000-0000-0000-000000000001'$$,
  '42501', null, 'El username NO es editable por el usuario (privilegio de columna)'
);

select * from finish();
rollback;
