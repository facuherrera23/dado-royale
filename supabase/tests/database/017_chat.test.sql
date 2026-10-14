-- Tests Fase 18: chat en mesas
begin;
select plan(4);

insert into auth.users (id, email, raw_user_meta_data, aud, role, email_confirmed_at, created_at, updated_at)
values ('c0ffeeaa-0000-0000-0000-000000000001', 'chat1@test.dev', '{"username":"chatter1"}', 'authenticated', 'authenticated', now(), now(), now()),
       ('c0ffeeab-0000-0000-0000-000000000002', 'chat2@test.dev', '{"username":"chatter2"}', 'authenticated', 'authenticated', now(), now(), now());
update public.profiles set kyc_verified = true where username like 'chatter%';

-- chatter1 sentado en Bronce; chatter2 libre
insert into public.table_players (table_id, user_id, status)
select id, 'c0ffeeaa-0000-0000-0000-000000000001', 'seated' from public.tables where name = 'Mesa Bronce';

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0ffeeaa-0000-0000-0000-000000000001","role":"authenticated"}';

-- 1. El sentado puede hablar
select lives_ok($$select public.send_table_message(
  (select id from public.tables where name='Mesa Bronce'), 'Hola a todos')$$,
  'El jugador sentado puede chatear');

-- 2. Rate limit 2s
select throws_ok($$select public.send_table_message(
  (select id from public.tables where name='Mesa Bronce'), 'Spam?')$$,
  'P0052', null, 'Rate limit: 1 mensaje / 2s');

-- 3. El espectador no sentado NO puede hablar
reset role;
update public.table_messages set created_at = now() - interval '10 seconds';
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0ffeeab-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.send_table_message(
  (select id from public.tables where name='Mesa Bronce'), 'Hola?')$$,
  'P0051', null, 'Quien no está en la mesa no puede hablar');

-- 4. INSERT directo prohibido
prepare chat_directo as insert into public.table_messages (table_id, user_id, body)
  values ((select id from public.tables limit 1), 'c0ffeeab-0000-0000-0000-000000000002', 'x');
select throws_ok('chat_directo', '42501', null, 'INSERT directo a table_messages prohibido');

select * from finish();
rollback;
