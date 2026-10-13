-- Tests Fase 16: KYC obligatorio para jugar.
begin;
select plan(7);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('bbbb0001-0000-0000-0000-000000000001', 'kyc@test.dev', '{"username":"kyctester"}', 'authenticated', 'authenticated', now(), now(), now());
update public.wallets set balance = 500 where user_id = 'bbbb0001-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbb0001-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. Sin KYC no puede sentarse en ninguna mesa
select throws_ok($$select public.join_table((select id from public.tables where name = 'Mesa Bronce'))$$,
  'P0035', null, 'join_table exige KYC antes de sentarse');

-- 2. Menores de 18 años: rechazado
select throws_ok($$select public.submit_kyc('Jo Menor', '2010-01-01'::date, 'ES', 'DNI1234567')$$,
  'P0032', null, 'submit_kyc rechaza a menores de 18');

-- 3. Nombre sin apellido: rechazado
select throws_ok($$select public.submit_kyc('SoloNombre', '1990-05-15'::date, 'ES', 'DNI1234567')$$,
  'P0030', null, 'submit_kyc exige nombre y apellido');

-- 4. País inválido (no ISO 2 letras): rechazado
select throws_ok($$select public.submit_kyc('Ana García', '1990-05-15'::date, 'ESPANA', 'DNI1234567')$$,
  'P0033', null, 'submit_kyc exige país ISO de 2 letras');

-- 5. KYC válido: verificado
select is(
  (public.submit_kyc('Ana Garcia', '1990-05-15'::date, 'ES', 'DNI1234567') ->> 'kyc_verified')::boolean,
  true,
  'KYC válido verifica al usuario'
);

-- 6. El documento NO se guarda en claro
reset role;
select ok(
  (select doc_hash ~ '^[0-9a-f]{64}$' from public.profiles where username = 'kyctester')
  and (select doc_hash <> upper('DNI1234567') from public.profiles where username = 'kyctester'),
  'El documento se guarda solo como hash SHA-256'
);

-- 7. Tras verificar, ya puede sentarse
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbb0001-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  public.join_table((select id from public.tables where name = 'Mesa Bronce')) ->> 'status',
  'seated',
  'Con KYC verificado, el jugador ya puede sentarse'
);

select * from finish();
rollback;
