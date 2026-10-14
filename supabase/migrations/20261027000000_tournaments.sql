-- =============================================================
-- Fase 19 · Torneos programados
--
--  * tournaments: buy-in, ventana temporal, estado, min jugadores.
--  * tournament_players: inscripción con buy-in bloqueado (ledger
--    'buy_in', espejo a la casa). Puntuación = neto de ledger en
--    rondas del juego dentro de la ventana.
--  * finalize_tournament(): al cerrar la ventana reparte 50/30/20
--    del pozo (menos 4% casa) al top 3; sin suficientes jugadores:
--    reembolso total. Idempotente. Se puede llamar por cron.
--  * ledger: columna tournament_id + tipos 'buy_in' y 'prize'.
-- =============================================================

alter type public.ledger_type add value 'buy_in';
alter type public.ledger_type add value 'prize';

create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  game text not null check (game in ('dice','poker','blackjack','war','rps')),
  buy_in bigint not null check (buy_in > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  min_players int not null default 2 check (min_players >= 2),
  status text not null default 'scheduled' check (status in ('scheduled','running','finished','cancelled')),
  created_at timestamptz not null default now()
);

create table public.tournament_players (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);

alter table public.tournaments enable row level security;
alter table public.tournament_players enable row level security;
alter table public.ledger
  add column tournament_id uuid references public.tournaments (id) on delete restrict;
create policy "tournaments: lectura pública" on public.tournaments for select using (true);
create policy "tournament_players: lectura pública" on public.tournament_players for select using (true);
revoke insert, update, delete on public.tournaments from anon, authenticated;
revoke insert, update, delete on public.tournament_players from anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.tournaments;
    alter publication supabase_realtime add table public.tournament_players;
  end if;
end $$;

insert into public.config (key, value, description) values
  ('tourn_prize_1', '50', 'Premio al 1º (% del pozo neto)'),
  ('tourn_prize_2', '30', 'Premio al 2º (% del pozo neto)'),
  ('tourn_prize_3', '20', 'Premio al 3º (% del pozo neto)');

-- ----------------------------------------------------------------
-- register_tournament: inscripción con buy-in bloqueado
-- ----------------------------------------------------------------
create or replace function public.register_tournament(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_t public.tournaments%rowtype;
  v_balance bigint;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;
  if not coalesce((select kyc_verified from public.profiles where id = v_uid), false) then
    raise exception 'Verifica tu identidad (KYC) antes de jugar' using errcode = 'P0035';
  end if;

  select * into v_t from public.tournaments where id = p_tournament_id for update;
  if not found then
    raise exception 'El torneo no existe' using errcode = 'P0060';
  end if;
  if v_t.status not in ('scheduled','running') or v_t.ends_at <= now() then
    raise exception 'El torneo ya cerró inscripciones' using errcode = 'P0061';
  end if;
  if exists (select 1 from public.tournament_players
             where tournament_id = p_tournament_id and user_id = v_uid) then
    return jsonb_build_object('tournament_id', p_tournament_id, 'status', 'registered');
  end if;

  update public.wallets set balance = balance - v_t.buy_in, updated_at = now()
   where user_id = v_uid and balance >= v_t.buy_in
  returning balance into v_balance;
  if not found then
    raise exception 'Saldo insuficiente para la inscripción (% fichas)', v_t.buy_in
      using errcode = 'P0009';
  end if;

  insert into public.tournament_players (tournament_id, user_id)
  values (p_tournament_id, v_uid);

  insert into public.ledger (user_id, type, amount, balance_after, tournament_id, idempotency_key)
  values (v_uid, 'buy_in', -v_t.buy_in, v_balance, p_tournament_id,
          'buyin:' || p_tournament_id::text || ':' || v_uid::text)
  on conflict (idempotency_key) do nothing;

  -- La casa recibe los buy-ins (espejo; los premios se descontarán en finalize)
  update public.house_account set balance = balance + v_t.buy_in, updated_at = now() where id = true;
  insert into public.ledger (user_id, type, amount, tournament_id, idempotency_key)
  values (null, 'house_settlement', v_t.buy_in, p_tournament_id,
          'buyinhouse:' || p_tournament_id::text || ':' || v_uid::text)
  on conflict (idempotency_key) do nothing;

  -- Estado derivado: running si ya empezó
  update public.tournaments set status = 'running'
   where id = p_tournament_id and starts_at <= now() and ends_at > now();

  return jsonb_build_object('tournament_id', p_tournament_id, 'status', 'registered');
end;
$$;

-- ----------------------------------------------------------------
-- finalize_tournament: premios 50/30/20 + comisión, o reembolso
-- ------------------------------------------------------------------
create or replace function public.finalize_tournament(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t public.tournaments%rowtype;
  v_n int;
  v_fee_pct bigint;
  v_pot bigint;
  v_fee bigint;
  v_stat record;
  v_rank int := 0;
  v_prize bigint;
  v_pct bigint;
  v_balance bigint;
  v_timeout interval;
begin
  select * into v_t from public.tournaments where id = p_tournament_id for update;
  if not found then
    raise exception 'El torneo no existe' using errcode = 'P0060';
  end if;
  if v_t.status in ('finished','cancelled') then
    return jsonb_build_object('tournament_id', p_tournament_id, 'status', v_t.status);
  end if;

  v_timeout := make_interval(secs => public.config_int('round_timeout_seconds')::int);
  if v_t.ends_at > now() - v_timeout then
    raise exception 'El torneo aún no ha terminado hace suficiente tiempo' using errcode = 'P0062';
  end if;

  select count(*) into v_n from public.tournament_players where tournament_id = p_tournament_id;

  if v_n < v_t.min_players then
    -- Reembolso: la casa devuelve los buy-ins
    for v_stat in
      select user_id from public.tournament_players where tournament_id = p_tournament_id
    loop
      update public.wallets set balance = balance + v_t.buy_in, updated_at = now()
       where user_id = v_stat.user_id returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, tournament_id, idempotency_key)
      values (v_stat.user_id, 'refund', v_t.buy_in, v_balance, p_tournament_id,
              'trefund:' || p_tournament_id::text || ':' || v_stat.user_id::text)
      on conflict (idempotency_key) do nothing;
      update public.house_account set balance = balance - v_t.buy_in, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, tournament_id, idempotency_key)
      values (null, 'house_settlement', -v_t.buy_in, p_tournament_id,
              'trefundhouse:' || p_tournament_id::text || ':' || v_stat.user_id::text)
      on conflict (idempotency_key) do nothing;
    end loop;

    update public.tournaments set status = 'cancelled' where id = p_tournament_id;
    return jsonb_build_object('tournament_id', p_tournament_id, 'status', 'cancelled',
                              'reason', 'not_enough_players');
  end if;

  v_fee_pct := public.config_int('house_fee_percent');
  v_pot := v_t.buy_in * v_n;
  v_fee := floor(v_pot * v_fee_pct::numeric / 100)::bigint;
  -- El resto (pozo - comisión) se reparte 50/30/20; el polvo redondea a la casa
  declare
    v_net bigint := v_pot - v_fee;
    v_p1 bigint := v_net * public.config_int('tourn_prize_1') / 100;
    v_p2 bigint := v_net * public.config_int('tourn_prize_2') / 100;
    v_p3 bigint := v_net * public.config_int('tourn_prize_3') / 100;
  begin
    for v_stat in
      with scores as (
        select tp.user_id,
               -- neto real del juego en la ventana: payouts + bet_lock(-) + refunds(+)
               coalesce(sum(l.amount), 0) as net
          from public.tournament_players tp
          left join public.ledger l
            on l.user_id = tp.user_id and l.type in ('payout','bet_lock','refund')
           and l.round_id in (
             select r.id from public.rounds r
              join public.tables t on t.id = r.table_id
             where t.game = v_t.game and r.status = 'finished'
               and r.created_at between v_t.starts_at and v_t.ends_at)
          where tp.tournament_id = p_tournament_id
          group by tp.user_id
      )
      select user_id, net from scores order by net desc, user_id limit 3
    loop
      v_rank := v_rank + 1;
      v_pct := least(case v_rank when 1 then public.config_int('tourn_prize_1')
                                 when 2 then public.config_int('tourn_prize_2')
                                 else public.config_int('tourn_prize_3') end, 100);
      v_prize := v_net * v_pct / 100;
      if v_prize <= 0 then continue; end if;

      update public.wallets set balance = balance + v_prize, updated_at = now()
       where user_id = v_stat.user_id returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, tournament_id, idempotency_key)
      values (v_stat.user_id, 'prize', v_prize, v_balance, p_tournament_id,
              'tprize:' || p_tournament_id::text || ':' || v_stat.user_id::text)
      on conflict (idempotency_key) do nothing;
      update public.house_account set balance = balance - v_prize, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, tournament_id, idempotency_key)
      values (null, 'house_settlement', -v_prize, p_tournament_id,
              'tprizehouse:' || p_tournament_id::text || ':' || v_stat.user_id::text)
      on conflict (idempotency_key) do nothing;
    end loop;

    -- Comisión al pozo de la casa (ya la tenía de los buy-ins; asiento informativo)
    insert into public.ledger (user_id, type, amount, tournament_id, idempotency_key)
    values (null, 'house_fee', v_fee, p_tournament_id, 'tfee:' || p_tournament_id::text)
    on conflict (idempotency_key) do nothing;
    -- Nota: v_net pueda quedar "polvo" no repartido -> se queda en la casa.
    update public.tournaments set status = 'finished' where id = p_tournament_id;
  end;

  return jsonb_build_object('tournament_id', p_tournament_id, 'status', 'finished',
                            'pot', v_pot, 'fee', v_fee);
end;
$$;

revoke all on function public.register_tournament(uuid) from public, anon;
revoke all on function public.finalize_tournament(uuid) from public, anon;
grant execute on function public.register_tournament(uuid) to authenticated;
grant execute on function public.finalize_tournament(uuid) to authenticated;

-- Finalización automática cerca del cierre
create or replace function public.finalize_due_tournaments()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t record;
  v_timeout interval;
  v_n int := 0;
begin
  v_timeout := make_interval(secs => public.config_int('round_timeout_seconds')::int);
  for v_t in
    select id from public.tournaments
     where status in ('scheduled','running') and ends_at <= now() - v_timeout
  loop
    perform public.finalize_tournament(v_t.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

revoke all on function public.finalize_due_tournaments() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('finalize-due-tournaments', '*/5 * * * *',
                          $cron$select public.finalize_due_tournaments()$cron$);
  end if;
end $$;
-- Standings en vivo: puntuación neta de cada inscrito en la ventana del torneo
create or replace function public.get_tournament_standings(p_tournament_id uuid)
returns table (username text, net bigint, won bigint)
language sql
stable
security definer
set search_path = public
as $$
  select pr.username,
         coalesce(sum(l.amount), 0) as net,
         coalesce(count(distinct rp.round_id) filter (
           where rp.is_winner or rp.result in ('win','blackjack')), 0) as won
    from public.tournament_players tp
    join public.profiles pr on pr.id = tp.user_id
    left join public.ledger l
      on l.user_id = tp.user_id and l.type in ('payout','bet_lock','refund')
     and l.round_id in (
       select r.id from public.rounds r
        join public.tables t on t.id = r.table_id
       where t.game = (select game from public.tournaments where id = p_tournament_id)
         and r.status = 'finished'
         and r.created_at between
             (select starts_at from public.tournaments where id = p_tournament_id)
             and (select ends_at from public.tournaments where id = p_tournament_id))
    left join public.round_players rp
      on rp.user_id = tp.user_id
     and rp.round_id in (
       select r2.id from public.rounds r2
        join public.tables t2 on t2.id = r2.table_id
       where t2.game = (select game from public.tournaments where id = p_tournament_id)
         and r2.status = 'finished'
         and r2.created_at between
             (select starts_at from public.tournaments where id = p_tournament_id)
             and (select ends_at from public.tournaments where id = p_tournament_id))
   where tp.tournament_id = p_tournament_id
   group by pr.username
   order by net desc, won desc, pr.username;
$$;

revoke all on function public.get_tournament_standings(uuid) from public, anon;
grant execute on function public.get_tournament_standings(uuid) to authenticated;

-- Seed: torneos semanales por juego
insert into public.tournaments (name, game, buy_in, starts_at, ends_at, min_players) values
  ('Torneo Semanal de Dados', 'dice', 100, date_trunc('week', now()), date_trunc('week', now()) + interval '7 days', 2),
  ('Torneo Semanal de Blackjack', 'blackjack', 250, date_trunc('week', now()), date_trunc('week', now()) + interval '7 days', 2),
  ('Torneo Semanal de Guerra', 'war', 50, date_trunc('week', now()), date_trunc('week', now()) + interval '7 days', 2);
