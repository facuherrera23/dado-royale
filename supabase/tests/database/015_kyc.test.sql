-- Tests Fase 16 (actualizado a Fase 17): gate KYC para jugar.
-- Nota: la verificación instantánea se eliminó; la aprobación real va por
-- submit_kyc + review_kyc (ver 016_kyc_real.test.sql). Aquí solo el gate.
begin;
select plan(2);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('bbbb0001-0000-0000-0000-000000000001', 'kyc@test.dev', '{"username":"kyctester"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 500 where user_id = 'bbbb0001-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbb0001-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. Sin verificar: no puede sentarse
select throws_ok($$select public.join_table((select id from public.tables where name = 'Mesa Bronce'))$$,
  'P0035', null, 'join_table exige KYC antes de sentarse');

-- 2. Verificado (como lo hace review_kyc): ya puede
reset role;
update public.profiles set kyc_verified = true, kyc_status = 'verified'
 where username = 'kyctester';
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbb0001-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  public.join_table((select id from public.tables where name = 'Mesa Bronce')) ->> 'status',
  'seated',
  'Tras KYC aprobado puede sentarse'
);

select * from finish();
rollback;
