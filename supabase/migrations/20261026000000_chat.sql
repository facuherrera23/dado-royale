-- =============================================================
-- Fase 18 · Chat en mesas
--
--  * table_messages: lectura pública (Realtime), escritura SOLO
--    vía RPC con rate limit (2s) y validación (1..500 chars).
--    RLS: inserts directos denegados (grant revocado); select all.
-- =============================================================

create table public.table_messages (
  id bigint generated always as identity primary key,
  table_id uuid not null references public.tables (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);

create index table_messages_table_idx on public.table_messages (table_id, id desc);

alter table public.table_messages enable row level security;
create policy "chat: lectura pública" on public.table_messages for select using (true);
revoke insert, update, delete on public.table_messages from anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.table_messages;
  end if;
end $$;

create or replace function public.send_table_message(p_table_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_last timestamptz;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;
  p_body := trim(p_body);
  if char_length(p_body) < 1 or char_length(p_body) > 500 then
    raise exception 'El mensaje debe tener entre 1 y 500 caracteres' using errcode = 'P0050';
  end if;

  -- Solo sentados (o espectadores con KYC) pueden hablar en la mesa
  if not exists (
    select 1 from public.table_players
     where table_id = p_table_id and user_id = v_uid and status = 'seated'
  ) then
    raise exception 'Solo quienes están en la mesa pueden hablar' using errcode = 'P0051';
  end if;

  -- Rate limit: 1 mensaje cada 2 segundos
  select max(created_at) into v_last from public.table_messages where user_id = v_uid;
  if v_last is not null and v_last + interval '2 seconds' > now() then
    raise exception 'Escribe más despacio' using errcode = 'P0052';
  end if;

  insert into public.table_messages (table_id, user_id, body)
  values (p_table_id, v_uid, p_body);

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.send_table_message(uuid, text) from public, anon;
grant execute on function public.send_table_message(uuid, text) to authenticated;
