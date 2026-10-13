-- Tests Fase 17: KYC real con cola de revisión.
begin;
select plan(10);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('c0ffee01-0000-0000-0000-000000000001', 'ky1@test.dev', '{"username":"kycr1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('c0ffee02-0000-0000-0000-000000000002', 'adm@test.dev', '{"username":"kycadmin"}', 'authenticated', 'authenticated', now(), now(), now());
update public.profiles set is_admin = true where username = 'kycadmin';
update public.profiles set kyc_status = 'unverified', kyc_verified = false where username = 'kycr1';
update public.wallets set balance = 1000 where user_id = 'c0ffee01-0000-0000-0000-000000000001';

-- Simulamos la subida del documento (fixture en storage.objects)
insert into storage.buckets (id, name, public) values ('kyc-documents','kyc-documents', false) on conflict do nothing;
insert into storage.objects (id, bucket_id, name, owner, created_at, updated_at)
values (gen_random_uuid(), 'kyc-documents', 'c0ffee01-0000-0000-0000-000000000001/front.jpg',
        'c0ffee01-0000-0000-0000-000000000001', now(), now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0ffee01-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. Sin el documento en tu carpeta (ruta inexistente): rechazado
select throws_ok($$select public.submit_kyc('Ana Garcia','1990-05-15'::date,'ES','dni','DNI1234567','c0ffee01-0000-0000-0000-000000000001/no-existe.jpg')$$,
  'P0036', null, 'submit_kyc exige el documento subido en tu carpeta');

-- 2. Menor de edad: rechazado
select throws_ok($$select public.submit_kyc('Pepe Nene','2012-01-01'::date,'ES','dni','DNI1234567','c0ffee01-0000-0000-0000-000000000001/front.jpg')$$,
  'P0032', null, 'submit_kyc rechaza a menores');

-- 3. Válido: queda pendiente
select is(
  (public.submit_kyc('Ana Garcia','1990-05-15'::date,'ES','dni','DNI1234567','c0ffee01-0000-0000-0000-000000000001/front.jpg') ->> 'kyc_status'),
  'pending', 'Solicitud KYC queda pendiente de revisión');

-- 4. Sin aprobación, no se puede jugar
select throws_ok($$select public.join_table((select id from public.tables where name='Mesa Bronce'))$$,
  'P0035', null, 'Pendiente de KYC: no puede sentarse en mesas');
select throws_ok($$select public.set_bet((select id from public.tables where name='Blackjack Bronce'), 50)$$,
  'P0035', null, 'Pendiente de KYC: no puede fijar apuesta');

-- 5. El usuario no puede escribir la solicitud directamente
prepare escribir_kyc as insert into public.kyc_submissions (user_id, full_name, date_of_birth, country, doc_type, doc_hash, doc_path_front)
  values ('c0ffee01-0000-0000-0000-000000000001','X X','1990-01-01','ES','dni','x','x');
select throws_ok('escribir_kyc', '42501', null, 'INSERT directo a kyc_submissions prohibido');

-- 6. Un no-admin no puede revisar
select throws_ok($$select public.review_kyc('c0ffee01-0000-0000-0000-000000000001'::uuid, true)$$,
  'P0403', null, 'review_kyc rechaza a no-admins');

-- 7. El admin Aprueba…
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0ffee02-0000-0000-0000-000000000002","role":"authenticated"}';
select is(
  (public.review_kyc((select id from public.kyc_submissions where status='pending'), true) ->> 'status'),
  'approved', 'El admin aprueba la solicitud');

-- 8. Perfil verificado tras aprobar; ya puede jugar
reset role;
select ok(
  (select kyc_verified from public.profiles where username='kycr1'),
  'Perfil marcado como verificado tras aprobación'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0ffee01-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  public.join_table((select id from public.tables where name='Mesa Bronce')) ->> 'status',
  'seated',
  'Verificado: ya puede sentarse en una mesa'
);

select * from finish();
rollback;
