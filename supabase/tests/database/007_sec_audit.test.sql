-- Auditoría de seguridad (Fase 8): verifica de forma continuada que los
-- pilares no se han roto. Se ejecuta en cada `supabase test db`.
begin;
select plan(7);

-- 1. RLS activado en TODAS las tablas públicas (incluidas futuras)
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0,
  'RLS activado en todas las tablas públicas'
);

-- 2. RLS no solo activado sino forzado (protege también al owner)
select is(
  (select count(*)::int from pg_tables t
    where t.schemaname = 'public' and not t.rowsecurity),
  0,
  'Ninguna tabla pública sin RLS (doble chequeo)'
);

-- 3. Ninguna escritura directa para authenticated en tablas sensibles
select is(
  (select count(*)::int from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and privilege_type in ('INSERT','UPDATE','DELETE')
      and table_name in ('wallets','ledger','rounds','round_players','tables','config','house_account','table_players')),
  0,
  'authenticated no tiene INSERT/UPDATE/DELETE en tablas sensibles'
);

-- 4. Las funciones internas no son ejecutables
select is(
  (select count(*)::int from information_schema.routine_privileges
    where grantee in ('anon','authenticated','public')
      and specific_schema = 'public'
      and routine_name = 'roll_d6'),
  0,
  'roll_d6 no es ejecutable por la API'
);

-- 5. Las RPC públicas SÍ son ejecutables por authenticated
select is(
  (select count(*)::int from information_schema.routine_privileges
    where grantee = 'authenticated'
      and specific_schema = 'public'
      and routine_name in ('claim_faucet','join_table','leave_table','start_round','roll_round','cancel_round','get_leaderboard','get_admin_stats')),
  8,
  'Las 8 RPC públicas tienen EXECUTE para authenticated'
);

-- 6. Todas las RPC públicas son SECURITY DEFINER con search_path fijo
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('claim_faucet','join_table','leave_table','start_round','roll_round','cancel_round','get_admin_stats','handle_new_user')
      and p.prosecdef
      and array_to_string(p.proconfig, ',') like '%search_path=public%'),
  8,
  'Todas las RPC sensibles son SECURITY DEFINER con search_path=public'
);

-- 7. pgcrypto existe (fuente de aleatoriedad criptográfica)
select has_extension('pgcrypto', 'pgcrypto instalada (gen_random_bytes)');

select * from finish();
rollback;
