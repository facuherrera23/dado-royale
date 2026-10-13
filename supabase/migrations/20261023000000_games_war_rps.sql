-- =============================================================
-- Fase 15 · Guerra de cartas + Piedra-Papel-Tijera (PvP)
--
--  * war: cada jugador recibe 1 carta criptográfica; gana el valor
--    más alto. Empate -> re-reparten los empatados (máx 3).
--  * rps: elección 1=piedra 2=papel 3=tijeras guardada en tabla OCULTA
--    (sin acceso API/Realtime) hasta que todos eligen.
--    Con 2 opciones distintas gana quien vence (piedra > tijeras > papel);
--    si hay 3 opciones o todos igual -> empate entre los mejores.
--  * Ambos usan la misma comisión del 4%, ledger cuadrado y refunds.
-- =============================================================

alter table public.tables drop constraint tables_game_check;
alter table public.tables
  add constraint tables_game_check check (game in ('dice','poker','blackjack','war','rps'));

insert into public.tables (name, bet_amount, max_players, game) values
  ('Guerra Bronce',    10,  6, 'war'),
  ('Guerra Plata',     50,  6, 'war'),
  ('Guerra Oro',       100, 5, 'war'),
  ('Guerra Diamante',  500, 4, 'war'),
  ('RPS Bronce',       10,  6, 'rps'),
  ('RPS Plata',        50,  6, 'rps'),
  ('RPS Oro',          100, 5, 'rps'),
  ('RPS Diamante',     500, 4, 'rps');

-- Elecciones ocultas de RPS (inaccesible desde la API)
create table public.round_rps_choices (
  round_id uuid not null references public.rounds (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  choice smallint not null check (choice between 1 and 3),
  tiebreak_no smallint not null default 0,
  primary key (round_id, user_id, tiebreak_no)
);
alter table public.round_rps_choices enable row level security;
revoke all on public.round_rps_choices from anon, authenticated;

-- ------------------------------------------------------------------
-- WAR: el jugador roba 1 carta; al tenerlas todos se resuelve
-- ------------------------------------------------------------------
create or replace function public._roll_round_war(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
  v_all boolean;
  v_winners uuid[];
  v_max_ties int;
  v_fee_pct bigint;
  v_fee bigint;
  v_prize bigint;
  v_balance bigint;
  v_player record;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;
  select r.* into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'La ronda no existe' using errcode = 'P0013';
  end if;
  if v_round.status <> 'in_progress' then
    return jsonb_build_object('round_id', p_round_id, 'status', v_round.status,
                              'winner_id', v_round.winner_id);
  end if;
  if not exists (select 1 from public.round_players
                 where round_id = p_round_id and user_id = v_uid) then
    raise exception 'No participas en esta ronda' using errcode = 'P0014';
  end if;

  update public.round_players
     set card1 = public.draw_card(p_round_id),
         tiebreak_attempts = v_round.tiebreak_round
   where round_id = p_round_id and user_id = v_uid and hand_no = 1 and card1 is null;

  select not exists (select 1 from public.round_players
                     where round_id = p_round_id and card1 is null)
    into v_all;
  if not v_all then
    return jsonb_build_object('round_id', p_round_id, 'status', 'waiting_rolls');
  end if;

  select array_agg(rp.user_id) into v_winners
    from public.round_players rp
   where rp.round_id = p_round_id
     and public.card_rank(rp.card1) = (select max(public.card_rank(rp2.card1))
                                         from public.round_players rp2
                                        where rp2.round_id = p_round_id);

  v_max_ties := public.config_int('max_tiebreaks')::int;
  v_fee_pct := public.config_int('house_fee_percent');

  if cardinality(v_winners) = 1 or v_round.tiebreak_round >= v_max_ties then
    if cardinality(v_winners) > 1 then
      for v_player in
        select rp.user_id, rp.bet_amount from public.round_players rp
         where rp.round_id = p_round_id order by rp.user_id
      loop
        update public.wallets set balance = balance + v_player.bet_amount, updated_at = now()
         where user_id = v_player.user_id returning balance into v_balance;
        insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
        values (v_player.user_id, 'refund', v_player.bet_amount, v_balance, p_round_id,
                'refund:' || p_round_id::text || ':' || v_player.user_id::text)
        on conflict (idempotency_key) do nothing;
      end loop;
      update public.rounds set status = 'cancelled', finished_at = now() where id = p_round_id;
      update public.tables set status = 'open' where id = v_round.table_id;
      return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled', 'reason', 'tiebreak_exhausted');
    end if;

    v_fee   := floor(v_round.pot * v_fee_pct::numeric / 100)::bigint;
    v_prize := v_round.pot - v_fee;

    update public.wallets set balance = balance + v_prize, updated_at = now()
     where user_id = v_winners[1] returning balance into v_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_winners[1], 'payout', v_prize, v_balance, p_round_id, 'payout:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;
    update public.house_account set balance = balance + v_fee, updated_at = now() where id = true;
    insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
    values (null, 'house_fee', v_fee, p_round_id, 'housefee:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;

    update public.rounds
       set status = 'finished', winner_id = v_winners[1], house_fee = v_fee, finished_at = now()
     where id = p_round_id;
    update public.round_players set is_winner = true
     where round_id = p_round_id and user_id = v_winners[1];
    update public.tables set status = 'open' where id = v_round.table_id;
    return jsonb_build_object('round_id', p_round_id, 'status', 'finished',
                              'winner_id', v_winners[1], 'pot', v_round.pot,
                              'house_fee', v_fee, 'prize', v_prize);
  end if;

  update public.rounds set tiebreak_round = tiebreak_round + 1 where id = p_round_id;
  update public.round_players set card1 = null
   where round_id = p_round_id and user_id = any (v_winners);
  return jsonb_build_object('round_id', p_round_id, 'status', 'tiebreak',
                            'tied_players', v_winners);
end;
$$;

-- ------------------------------------------------------------------
-- RPS: cada jugador registra su elección (oculta); al completar se
-- compara y se paga como los demás juegos PvP.
-- ------------------------------------------------------------------
create or replace function public.rps_play(p_round_id uuid, p_choice smallint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
  v_all boolean;
  v_winners uuid[];
  v_distinct int;
  v_max_ties int;
  v_fee_pct bigint;
  v_fee bigint;
  v_prize bigint;
  v_balance bigint;
  v_player record;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;
  if p_choice not in (1, 2, 3) then
    raise exception 'Elección inválida (1=piedra, 2=papel, 3=tijeras)' using errcode = 'P0019';
  end if;

  select r.* into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'La ronda no existe' using errcode = 'P0013';
  end if;
  if v_round.status <> 'in_progress' then
    return jsonb_build_object('round_id', p_round_id, 'status', v_round.status);
  end if;
  if not exists (select 1 from public.round_players
                 where round_id = p_round_id and user_id = v_uid) then
    raise exception 'No participas en esta ronda' using errcode = 'P0014';
  end if;

  -- Registro idempotente/idempotente-por-desempate de la elección oculta
  insert into public.round_rps_choices (round_id, user_id, choice, tiebreak_no)
  values (p_round_id, v_uid, p_choice, v_round.tiebreak_round)
  on conflict (round_id, user_id, tiebreak_no) do nothing;

  select not exists (
    select 1 from public.round_players rp
     where rp.round_id = p_round_id
       and not exists (select 1 from public.round_rps_choices c
                        where c.round_id = rp.round_id and c.user_id = rp.user_id
                          and c.tiebreak_no = v_round.tiebreak_round)
  ) into v_all;
  if not v_all then
    return jsonb_build_object('round_id', p_round_id, 'status', 'waiting_choices');
  end if;

  -- Resolver: si hay exactamente 2 elecciones distintas, una vence
  select count(distinct c.choice) into v_distinct
    from public.round_rps_choices c
   where c.round_id = p_round_id and c.tiebreak_no = v_round.tiebreak_round;

  if v_distinct = 2 then
    select array_agg(c.user_id) into v_winners
      from public.round_rps_choices c
     where c.round_id = p_round_id and c.tiebreak_no = v_round.tiebreak_round
       -- regla circular: 1>3, 3>2, 2>1
       and (c.choice, (select min(c2.choice) from public.round_rps_choices c2
                         where c2.round_id = p_round_id and c2.tiebreak_no = v_round.tiebreak_round
                           and c2.choice <> c.choice)) in ((1,3), (3,2), (2,1));
  else
    -- Todos igual o 3 opciones => empate total, todos re-eligen
    select array_agg(rp.user_id) into v_winners from public.round_players rp
     where rp.round_id = p_round_id;
  end if;

  v_max_ties := public.config_int('max_tiebreaks')::int;
  v_fee_pct := public.config_int('house_fee_percent');

  if cardinality(v_winners) = 1 or v_round.tiebreak_round >= v_max_ties then
    if cardinality(v_winners) > 1 then
      for v_player in
        select rp.user_id, rp.bet_amount from public.round_players rp
         where rp.round_id = p_round_id order by rp.user_id
      loop
        update public.wallets set balance = balance + v_player.bet_amount, updated_at = now()
         where user_id = v_player.user_id returning balance into v_balance;
        insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
        values (v_player.user_id, 'refund', v_player.bet_amount, v_balance, p_round_id,
                'refund:' || p_round_id::text || ':' || v_player.user_id::text)
        on conflict (idempotency_key) do nothing;
      end loop;
      update public.rounds set status = 'cancelled', finished_at = now() where id = p_round_id;
      delete from public.round_rps_choices where round_id = p_round_id;
      update public.tables set status = 'open' where id = v_round.table_id;
      return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled', 'reason', 'tiebreak_exhausted');
    end if;

    v_fee   := floor(v_round.pot * v_fee_pct::numeric / 100)::bigint;
    v_prize := v_round.pot - v_fee;

    update public.wallets set balance = balance + v_prize, updated_at = now()
     where user_id = v_winners[1] returning balance into v_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_winners[1], 'payout', v_prize, v_balance, p_round_id, 'payout:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;
    update public.house_account set balance = balance + v_fee, updated_at = now() where id = true;
    insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
    values (null, 'house_fee', v_fee, p_round_id, 'housefee:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;

    update public.rounds
       set status = 'finished', winner_id = v_winners[1], house_fee = v_fee, finished_at = now()
     where id = p_round_id;
    update public.round_players set is_winner = true
     where round_id = p_round_id and user_id = v_winners[1];
    delete from public.round_rps_choices where round_id = p_round_id;
    update public.tables set status = 'open' where id = v_round.table_id;
    return jsonb_build_object('round_id', p_round_id, 'status', 'finished',
                              'winner_id', v_winners[1], 'pot', v_round.pot,
                              'house_fee', v_fee, 'prize', v_prize);
  end if;

  -- Empate: sube tiebreak y los empatados vuelven a elegir
  update public.rounds set tiebreak_round = tiebreak_round + 1 where id = p_round_id;
  return jsonb_build_object('round_id', p_round_id, 'status', 'tiebreak',
                            'tied_players', v_winners,
                            'tiebreak_round', v_round.tiebreak_round + 1);
end;
$$;

-- Dispatcher: dirige al juego correcto de la mesa
create or replace function public.roll_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game text;
begin
  select t.game into v_game
    from public.rounds r join public.tables t on t.id = r.table_id
   where r.id = p_round_id;
  if v_game = 'blackjack' then
    raise exception 'En blackjack usa bj_action (hit/stand/double/split/insurance)' using errcode = 'P0017';
  end if;
  if v_game = 'war' then
    return public._roll_round_war(p_round_id);
  end if;
  if v_game = 'rps' then
    raise exception 'En piedra-papel-tijera usa rps_play(round_id, eleccion)' using errcode = 'P0019';
  end if;
  return public._roll_round_dice_poker(p_round_id);
end;
$$;

grant execute on function public.rps_play(uuid, smallint) to authenticated;
revoke all on function public.rps_play(uuid, smallint) from public, anon;
grant execute on function public.rps_play(uuid, smallint) to authenticated;
revoke all on function public._roll_round_war(uuid) from public, anon, authenticated;
