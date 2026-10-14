-- =============================================================
-- Fase 20 · Logros, eventos de ronda (replay) y antifraude admin
-- =============================================================

-- ---------- Logros / misiones ----------
create table public.achievements (
  key text primary key,
  name text not null,
  description text not null,
  icon text not null default '🏅'
);

create table public.user_achievements (
  user_id uuid not null references public.profiles (id) on delete cascade,
  achievement_key text not null references public.achievements (key) on delete cascade,
  earned_at timestamptz not null default now(),
  primary key (user_id, achievement_key)
);

alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
create policy "achievements: lectura pública" on public.achievements for select using (true);
create policy "user_achievements: lectura pública" on public.user_achievements for select using (true);
revoke insert, update, delete on public.achievements from anon, authenticated;
revoke insert, update, delete on public.user_achievements from anon, authenticated;

insert into public.achievements (key, name, description, icon) values
  ('primera_victoria', '¡Primera victoria!',  'Gana tu primera ronda', '🏅'),
  ('natural_21',       '21 perfecto',          'Consigue un blackjack natural', '🃏'),
  ('seis_dobles',      'Pareja de seises',     'Saca 6+6 en una ronda de dados', '🎲'),
  ('veterano',         'Veterano de mesa',     'Juega 25 rondas', '🎖️'),
  ('trotamundos',      'Multi-juego',          'Gana en 3 juegos distintos', '🌍'),
  ('gran_apostador',   'Gran apostador',       'Gana una apuesta de 500+ fichas', '💎'),
  ('racha_semanal',    'Racha de la semana',   'Gana 3 rondas en una misma semana', '🔥');

-- check_achievements: evalúa y otorga; idempotente.
create or replace function public.check_achievements()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_new text[] := '{}';
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  -- primera victoria (cualquier juego)
  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'primera_victoria'
   where exists (select 1 from public.round_players rp
                  join public.rounds r on r.id = rp.round_id
                 where rp.user_id = v_uid and r.status = 'finished'
                   and (rp.is_winner or rp.result in ('win','blackjack')))
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'primera_victoria'); end if;

  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'natural_21'
   where exists (select 1 from public.round_players
                  where user_id = v_uid and result = 'blackjack')
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'natural_21'); end if;

  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'seis_dobles'
   where exists (select 1 from public.round_players rp
                  join public.rounds r on r.id = rp.round_id
                  join public.tables t on t.id = r.table_id
                 where rp.user_id = v_uid and t.game = 'dice'
                   and rp.dice1 = 6 and rp.dice2 = 6)
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'seis_dobles'); end if;

  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'veterano'
   where (select count(*) from public.round_players rp
           join public.rounds r on r.id = rp.round_id
          where rp.user_id = v_uid and r.status = 'finished') >= 25
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'veterano'); end if;

  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'trotamundos'
   where (select count(distinct t.game) from public.round_players rp
           join public.rounds r on r.id = rp.round_id
           join public.tables t on t.id = r.table_id
          where rp.user_id = v_uid and r.status = 'finished'
            and (rp.is_winner or rp.result in ('win','blackjack'))) >= 3
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'trotamundos'); end if;

  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'gran_apostador'
   where exists (select 1 from public.ledger
                  where user_id = v_uid and type = 'payout' and amount >= 1000)
   or exists (select 1 from public.round_players rp
               join public.rounds r on r.id = rp.round_id and r.status = 'finished'
               join public.tables t on t.id = r.table_id
              where rp.user_id = v_uid
                and (rp.is_winner or rp.result in ('win','blackjack'))
                and rp.bet_amount >= 500)
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'gran_apostador'); end if;

  insert into public.user_achievements (user_id, achievement_key)
  select v_uid, 'racha_semanal'
   where (select count(*) from public.round_players rp
           join public.rounds r on r.id = rp.round_id
          where rp.user_id = v_uid and r.status = 'finished'
            and (rp.is_winner or rp.result in ('win','blackjack'))
            and r.finished_at >= date_trunc('week', now())) >= 3
  on conflict do nothing;
  if found then v_new := array_append(v_new, 'racha_semanal'); end if;

  return jsonb_build_object('newly_earned', v_new);
end;
$$;

revoke all on function public.check_achievements() from public, anon;
grant execute on function public.check_achievements() to authenticated;

-- ---------- Eventos de ronda (replay) ----------
create table public.round_events (
  id bigint generated always as identity primary key,
  round_id uuid not null references public.rounds (id) on delete cascade,
  seq smallint not null,
  event_type text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  unique (round_id, seq)
);

alter table public.round_events enable row level security;
create policy "round_events: lectura pública" on public.round_events for select using (true);
revoke insert, update, delete on public.round_events from anon, authenticated;

create or replace function public.log_round_event(p_round_id uuid, p_type text, p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.round_events (round_id, seq, event_type, payload)
  select p_round_id,
         coalesce(max(seq), 0) + 1,
         p_type, p_payload
    from public.round_events where round_id = p_round_id;
end;
$$;

revoke all on function public.log_round_event(uuid, text, jsonb) from public, anon, authenticated;

-- ---------- Detección de fraude (admin) ----------
create or replace function public.admin_detect_patterns()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Solo administradores' using errcode = 'P0403';
  end if;

  return jsonb_build_object(
    'mismo_documento', (
      select coalesce(jsonb_agg(d), '[]') from (
        select doc_hash, array_agg(username order by username) as usuarios
          from public.profiles
         where doc_hash is not null
         group by doc_hash having count(*) > 1
      ) d),
    'parejas_sospechosas', (
      select coalesce(jsonb_agg(p), '[]') from (
        select j1.user_id as a, j2.user_id as b, count(*) as juntas,
               sum((j1.is_winner)::int) as wins_a
          from public.round_players j1
          join public.round_players j2
            on j1.round_id = j2.round_id and j1.user_id < j2.user_id
          join public.rounds r on r.id = j1.round_id and r.status = 'finished'
          join public.tables t on t.id = r.table_id and t.game in ('dice','poker','war','rps')
         group by j1.user_id, j2.user_id
        having count(*) >= 5
           and (sum((j1.is_winner)::int)::float / count(*) <= 0.2
                or sum((j1.is_winner)::int)::float / count(*) >= 0.8)
       ) p),
    'sin_jugar_con_faucet', (
      select coalesce(jsonb_agg(f), '[]') from (
        select pr.id, pr.username, count(*) as reclamos
          from public.ledger l join public.profiles pr on pr.id = l.user_id
         where l.type = 'faucet'
         group by pr.id, pr.username
        having count(*) >= 3
           and not exists (select 1 from public.round_players rp2 where rp2.user_id = pr.id)
       ) f)
  );
end;
$$;

revoke all on function public.admin_detect_patterns() from public, anon;
grant execute on function public.admin_detect_patterns() to authenticated;
