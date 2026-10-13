-- Tests de la Fase 7: ranking y control de acceso de administrador.
begin;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('eeeeeee1-0000-0000-0000-000000000001', 'admin@test.dev', '{"username":"admin_user"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('eeeeeee2-0000-0000-0000-000000000002', 'player@test.dev', '{"username":"player1"}', 'authenticated', 'authenticated', now(), now(), now());

-- Movimientos de muestra para el ranking
insert into public.ledger (user_id, type, amount, balance_after, idempotency_key)
values ('eeeeeee2-0000-0000-0000-000000000002', 'payout', 500, 500, 'payout-test-1');

set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeee2-0000-0000-0000-000000000002","role":"authenticated"}';

-- 1. El ranking refleja el payout del jugador
select is(
  (select total_won from public.get_leaderboard(10) where username = 'player1'),
  500::bigint,
  'get_leaderboard suma los payouts del jugador'
);

-- 2. Non-admin NO puede ejecutar get_admin_stats
select throws_ok($$select public.get_admin_stats()$$,
  'P0403', null, 'get_admin_stats rechaza a usuarios no admin');

-- 3. Non-admin NO ve la casa (RLS)
select is((select count(*)::int from public.house_account), 0,
  'RLS: un jugador no ve house_account');

-- 4. is_admin devuelve false para usuario normal
select is(public.is_admin('eeeeeee2-0000-0000-0000-000000000002'::uuid), false,
  'is_admin false para jugador normal');

-- 5-6. Promovido a admin (superusuario) → acceso concedido
reset role;
update public.profiles set is_admin = true where id = 'eeeeeee1-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeee1-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.get_admin_stats()$$,
  'get_admin_stats funciona para admin');
select is((select count(*)::int from public.house_account), 1,
  'RLS: el admin ve house_account');

select * from finish();
rollback;
