-- =============================================================
-- Fase 10 · Blackjack (21) con apuesta variable, vs la banca
--
--  * tables.game admite 'blackjack'; max_bet marca el tope.
--  * table_players.pending_bet: apuesta elegida (set_bet RPC).
--    Solo entran en la ronda los sentados con apuesta fijada.
--  * Blackjack es CONTRA LA BANCA: el pozo no es comunitario.
--    La casa cobra las apuestas perdedoras y paga las ganadoras
--    (ledger compensado: filas 'house_settlement'); NO hay
--    comisión del 4% en este juego (precio = ventaja de la banca).
--  * Pagos: gano normal => 2× apuesta (devuelve stake + premio 1:1)
--    blackjack natural => stake + ceil(1.5 × stake) (paga 3:2)
--    push => reembolso íntegro. Redondeo ceil favorece al jugador.
--  * Baraja sin repetición (incluye las cartas del dealer).
-- =============================================================

alter table public.tables drop constraint tables_game_check;
alter table public.tables
  add constraint tables_game_check check (game in ('dice','poker','blackjack'));

alter table public.tables
  add column max_bet bigint check (max_bet is null or max_bet >= bet_amount);

alter table public.table_players
  add column pending_bet bigint check (pending_bet is null or pending_bet > 0);

alter table public.rounds
  add column dealer_cards smallint[] not null default '{}';

alter table public.round_players
  add column cards smallint[] not null default '{}',
  add column stood boolean not null default false,
  add column result text check (result in ('win','blackjack','push','loss'));

alter type public.ledger_type add value 'house_settlement';

-- ----------------------------------------------------------------
-- Cartas: valor para blackjack (J/Q/K=10, A=11 o 1)
-- ----------------------------------------------------------------
create or replace function public.card_value(p_card smallint)
returns int
language sql
immutable
set search_path = public
as $$
  select case public.card_rank(p_card) when 14 then 11
         else least(public.card_rank(p_card)::int, 10) end;
$$;

-- hand_value: suma con ases flexibles (11 -> 1 si se pasa de 21)
create or replace function public.hand_value(p_cards smallint[])
returns int
language plpgsql
immutable
set search_path = public
as $$
declare
  v_total int;
  v_aces int;
begin
  select coalesce(sum(public.card_value(c)), 0),
         coalesce(sum(case when public.card_rank(c) = 14 then 1 else 0 end), 0)
    into v_total, v_aces
    from unnest(p_cards) as c;
  while v_total > 21 and v_aces > 0 loop
    v_total := v_total - 10;
    v_aces := v_aces - 1;
  end loop;
  return v_total;
end;
$$;

create or replace function public.is_blackjack(p_cards smallint[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select cardinality(p_cards) = 2 and public.hand_value(p_cards) = 21;
$$;

-- draw_card ahora también excluye las cartas del dealer
create or replace function public.draw_card(p_round uuid)
returns smallint
language plpgsql
volatile
set search_path = public
as $$
declare
  v_remaining smallint[];
  v_idx int;
  v_used smallint[];
begin
  select coalesce(array_agg(c), '{}') into v_used
    from (
      select unnest(rp.cards) as c from public.round_players rp
       where rp.round_id = p_round
      union all
      select card1 from public.round_players where round_id = p_round and card1 is not null
      union all
      select card2 from public.round_players where round_id = p_round and card2 is not null
      union all
      select unnest(r.dealer_cards) from public.rounds r where r.id = p_round
    ) u;

  v_remaining := array(
    select c::smallint from generate_series(1, 52) as g(c)
     where c::smallint <> all (coalesce(v_used, '{}'::smallint[]))
  );
  if array_length(v_remaining, 1) is null then
    raise exception 'No quedan cartas en la baraja' using errcode = 'P0051';
  end if;
  v_idx := public._uniform(array_length(v_remaining, 1));
  return v_remaining[v_idx];
end;
$$;

-- ----------------------------------------------------------------
-- set_bet: el jugador sentado elige su apuesta (solo blackjack)
-- ----------------------------------------------------------------
create or replace function public.set_bet(p_table_id uuid, p_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_table public.tables%rowtype;
  v_balance bigint;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  select * into v_table from public.tables where id = p_table_id for update;
  if not found then
    raise exception 'La mesa no existe' using errcode = 'P0004';
  end if;
  if v_table.game <> 'blackjack' then
    raise exception 'Esta mesa tiene apuesta fija' using errcode = 'P0017';
  end if;
  if v_table.status <> 'open' then
    raise exception 'Hay una ronda en curso en esta mesa' using errcode = 'P0011';
  end if;
  if not exists (select 1 from public.table_players
                 where table_id = p_table_id and user_id = v_uid and status = 'seated') then
    raise exception 'No estás sentado en esta mesa' using errcode = 'P0010';
  end if;
  if p_amount < v_table.bet_amount or p_amount > coalesce(v_table.max_bet, v_table.bet_amount) then
    raise exception 'La apuesta debe estar entre % y %', v_table.bet_amount, coalesce(v_table.max_bet, v_table.bet_amount)
      using errcode = 'P0018';
  end if;

  select balance into v_balance from public.wallets where user_id = v_uid for update;
  if v_balance is null or v_balance < p_amount then
    raise exception 'Saldo insuficiente' using errcode = 'P0009';
  end if;

  update public.table_players set pending_bet = p_amount
   where table_id = p_table_id and user_id = v_uid;

  return jsonb_build_object('table_id', p_table_id, 'pending_bet', p_amount);
end;
$$;

-- ----------------------------------------------------------------
-- bj_action: 'hit' (carta) o 'stand' (planta). Cuando todos están
-- plantados/rotos, el dealer roba hasta 17 y se liquida la ronda.
-- ----------------------------------------------------------------
create or replace function public.bj_action(p_round_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
  v_game text;
  v_my record;
  v_value int;
  v_dealer_cards smallint[];
  v_dealer_value int;
  v_dealer_natural boolean;
  v_player record;
  v_result text;
  v_pv int;
  v_natural boolean;
  v_winnings bigint;
  v_balance bigint;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;
  if p_action not in ('hit','stand') then
    raise exception 'Acción inválida (hit|stand)' using errcode = 'P0019';
  end if;

  select r.* into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'La ronda no existe' using errcode = 'P0013';
  end if;
  if v_round.status <> 'in_progress' then
    return jsonb_build_object('round_id', p_round_id, 'status', v_round.status);
  end if;

  select game into v_game from public.tables where id = v_round.table_id;
  if v_game <> 'blackjack' then
    raise exception 'Esta ronda no es de blackjack' using errcode = 'P0017';
  end if;

  select * into v_my from public.round_players
   where round_id = p_round_id and user_id = v_uid for update;
  if not found then
    raise exception 'No participas en esta ronda' using errcode = 'P0014';
  end if;
  if v_my.stood then
    return jsonb_build_object('round_id', p_round_id, 'status', 'already_stood');
  end if;

  if p_action = 'hit' then
    update public.round_players
       set cards = cards || public.draw_card(p_round_id)
     where round_id = p_round_id and user_id = v_uid;
    select public.hand_value(cards) into v_value from public.round_players
     where round_id = p_round_id and user_id = v_uid;
    if v_value > 21 then
      update public.round_players set stood = true, result = 'loss'
       where round_id = p_round_id and user_id = v_uid;
    end if;
  else
    update public.round_players set stood = true
     where round_id = p_round_id and user_id = v_uid;
  end if;

  -- ¿Todos terminaron? -> dealer juega y se liquida
  if exists (select 1 from public.round_players
             where round_id = p_round_id and not stood) then
    return jsonb_build_object('round_id', p_round_id, 'status', 'playing');
  end if;

  -- Dealer roba hasta 17
  v_dealer_cards := v_round.dealer_cards;
  while public.hand_value(v_dealer_cards) < 17 loop
    v_dealer_cards := v_dealer_cards || public.draw_card(p_round_id);
  end loop;
  update public.rounds set dealer_cards = v_dealer_cards where id = p_round_id;
  v_dealer_value := public.hand_value(v_dealer_cards);
  v_dealer_natural := public.is_blackjack(v_dealer_cards);

  for v_player in
    select rp.user_id, rp.bet_amount, rp.cards, rp.result
      from public.round_players rp where rp.round_id = p_round_id
     order by rp.user_id
  loop
    -- Los que se pasaron ya tienen result='loss'
    if v_player.result is null then
      v_pv := public.hand_value(v_player.cards);
      v_natural := public.is_blackjack(v_player.cards);
      if v_dealer_value > 21 then
        update public.round_players set result = 'win'
         where round_id = p_round_id and user_id = v_player.user_id;
      elsif v_natural and not v_dealer_natural then
        update public.round_players set result = 'blackjack'
         where round_id = p_round_id and user_id = v_player.user_id;
      elsif v_dealer_natural and not v_natural then
        update public.round_players set result = 'loss'
         where round_id = p_round_id and user_id = v_player.user_id;
      elsif v_natural and v_dealer_natural then
        update public.round_players set result = 'push'
         where round_id = p_round_id and user_id = v_player.user_id;
      elsif v_pv > v_dealer_value then
        update public.round_players set result = 'win'
         where round_id = p_round_id and user_id = v_player.user_id;
      elsif v_pv = v_dealer_value then
        update public.round_players set result = 'push'
         where round_id = p_round_id and user_id = v_player.user_id;
      else
        update public.round_players set result = 'loss'
         where round_id = p_round_id and user_id = v_player.user_id;
      end if;
    end if;

    select result into v_result from public.round_players
     where round_id = p_round_id and user_id = v_player.user_id;

    -- La banca cobra la apuesta SIEMPRE (recibe el stake al liquidar);
    -- y además paga/devuelve según el resultado, para cuadrar el ledger:
    --   loss: -b (bet_lock) + b (stake a casa)                     = 0
    --   push: -b + b (refund) + b (casa) - b (casa devuelve)        = 0
    --   win:  -b + b (casa) + 2b (payout) - 2b (casa paga)          = 0
    update public.house_account
       set balance = balance + v_player.bet_amount, updated_at = now() where id = true;
    insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
    values (null, 'house_settlement', v_player.bet_amount, p_round_id,
            'bjstake:' || p_round_id::text || ':' || v_player.user_id::text)
    on conflict (idempotency_key) do nothing;

    if v_result = 'push' then
      update public.wallets set balance = balance + v_player.bet_amount, updated_at = now()
       where user_id = v_player.user_id returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
      values (v_player.user_id, 'refund', v_player.bet_amount, v_balance, p_round_id,
              'bjpush:' || p_round_id::text || ':' || v_player.user_id::text)
      on conflict (idempotency_key) do nothing;
      update public.house_account
         set balance = balance - v_player.bet_amount, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
      values (null, 'house_settlement', -v_player.bet_amount, p_round_id,
              'bjhouserefund:' || p_round_id::text || ':' || v_player.user_id::text)
      on conflict (idempotency_key) do nothing;
    elsif v_result in ('win','blackjack') then
      -- win: 2× apuesta; blackjack: apuesta + ceil(1.5 × apuesta)
      v_winnings := case when v_result = 'blackjack'
                         then v_player.bet_amount + (v_player.bet_amount * 3 + 1) / 2
                         else v_player.bet_amount * 2 end;
      update public.wallets set balance = balance + v_winnings, updated_at = now()
       where user_id = v_player.user_id returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
      values (v_player.user_id, 'payout', v_winnings, v_balance, p_round_id,
              'bjpay:' || p_round_id::text || ':' || v_player.user_id::text)
      on conflict (idempotency_key) do nothing;
      update public.house_account
         set balance = balance - v_winnings, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
      values (null, 'house_settlement', -v_winnings, p_round_id,
              'bjhouseloss:' || p_round_id::text || ':' || v_player.user_id::text)
      on conflict (idempotency_key) do nothing;
    end if;
  end loop;

  update public.rounds
     set status = 'finished', finished_at = now()
   where id = p_round_id;
  update public.tables set status = 'open' where id = v_round.table_id;

  return jsonb_build_object('round_id', p_round_id, 'status', 'finished');
end;
$$;

-- ----------------------------------------------------------------
-- start_round: versión con soporte blackjack (pendiente_bet, baraja)
-- ----------------------------------------------------------------
create or replace function public.start_round(p_table_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_table public.tables%rowtype;
  v_round_id uuid;
  v_player record;
  v_min int;
  v_seated int;
  v_balance bigint;
  v_pot bigint;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  select * into v_table from public.tables where id = p_table_id for update;
  if not found then
    raise exception 'La mesa no existe' using errcode = 'P0004';
  end if;
  if v_table.status <> 'open' then
    raise exception 'La mesa ya tiene una ronda en curso' using errcode = 'P0005';
  end if;

  if not exists (select 1 from public.table_players
                 where table_id = p_table_id and user_id = v_uid and status = 'seated') then
    raise exception 'No estás sentado en esta mesa' using errcode = 'P0010';
  end if;

  if v_table.game = 'blackjack' then
    -- Solo entran los sentados con apuesta fijada
    select count(*) into v_seated from public.table_players
     where table_id = p_table_id and status = 'seated' and pending_bet is not null;
    if v_seated < 1 then
      raise exception 'Fija tu apuesta antes de empezar' using errcode = 'P0018';
    end if;
    if not exists (select 1 from public.table_players
                   where table_id = p_table_id and user_id = v_uid
                     and status = 'seated' and pending_bet is not null) then
      raise exception 'Fija tu apuesta para entrar en la ronda' using errcode = 'P0018';
    end if;

    insert into public.rounds (table_id, status)
    values (p_table_id, 'in_progress')
    returning id into v_round_id;

    insert into public.round_players (round_id, user_id, bet_amount)
    select v_round_id, user_id, pending_bet
      from public.table_players
     where table_id = p_table_id and status = 'seated' and pending_bet is not null;

    v_pot := 0;
    for v_player in
      select rp.user_id, rp.bet_amount from public.round_players rp
       where rp.round_id = v_round_id order by rp.user_id
    loop
      update public.wallets
         set balance = balance - v_player.bet_amount, updated_at = now()
       where user_id = v_player.user_id and balance >= v_player.bet_amount
      returning balance into v_balance;
      if not found then
        raise exception 'Saldo insuficiente para un jugador sentado' using errcode = 'P0009';
      end if;
      insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
      values (v_player.user_id, 'bet_lock', -v_player.bet_amount, v_balance, v_round_id,
              'bet:' || v_round_id::text || ':' || v_player.user_id::text)
      on conflict (idempotency_key) do nothing;
      v_pot := v_pot + v_player.bet_amount;
    end loop;

    -- Reparto inicial: 2 cartas por jugador y 2 al dealer (sin repetición)
    update public.round_players
       set cards = array[public.draw_card(v_round_id), public.draw_card(v_round_id)]
     where round_id = v_round_id;
    update public.rounds
       set dealer_cards = array[public.draw_card(v_round_id), public.draw_card(v_round_id)],
           pot = v_pot
     where id = v_round_id;

    update public.table_players set pending_bet = null
     where table_id = p_table_id;
    update public.tables set status = 'in_round' where id = p_table_id;
    return jsonb_build_object('round_id', v_round_id, 'pot', v_pot, 'players', v_seated);
  end if;

  -- Dados / Póker (apuesta fija del precio de la mesa)
  v_min := public.config_int('min_players')::int;
  select count(*) into v_seated from public.table_players
   where table_id = p_table_id and status = 'seated';
  if v_seated < v_min then
    raise exception 'Se necesitan al menos % jugadores (hay %)', v_min, v_seated
      using errcode = 'P0012';
  end if;

  insert into public.rounds (table_id, status)
  values (p_table_id, 'in_progress')
  returning id into v_round_id;

  insert into public.round_players (round_id, user_id, bet_amount)
  select v_round_id, user_id, v_table.bet_amount
    from public.table_players
   where table_id = p_table_id and status = 'seated';

  v_pot := 0;
  for v_player in
    select rp.user_id, rp.bet_amount from public.round_players rp
     where rp.round_id = v_round_id order by rp.user_id
  loop
    update public.wallets
       set balance = balance - v_player.bet_amount, updated_at = now()
     where user_id = v_player.user_id and balance >= v_player.bet_amount
    returning balance into v_balance;
    if not found then
      raise exception 'Saldo insuficiente para un jugador sentado' using errcode = 'P0009';
    end if;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_player.user_id, 'bet_lock', -v_player.bet_amount, v_balance, v_round_id,
            'bet:' || v_round_id::text || ':' || v_player.user_id::text)
    on conflict (idempotency_key) do nothing;
    v_pot := v_pot + v_player.bet_amount;
  end loop;

  update public.rounds set pot = v_pot where id = v_round_id;
  update public.tables set status = 'in_round' where id = p_table_id;
  return jsonb_build_object('round_id', v_round_id, 'pot', v_pot, 'players', v_seated);
end;
$$;

-- ----------------------------------------------------------------
-- Dispatcher: el roll_round de dados/póker pasa a ser interno y
-- roll_round dirige según el juego de la mesa.
-- ----------------------------------------------------------------
alter function public.roll_round(uuid) rename to _roll_round_dice_poker;

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
    raise exception 'En blackjack usa bj_action (hit/stand)' using errcode = 'P0017';
  end if;
  return public._roll_round_dice_poker(p_round_id);
end;
$$;

revoke all on function public._roll_round_dice_poker(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------
-- cancel_round: en blackjack solo si nadie ha actuado todavía.
-- ----------------------------------------------------------------
create or replace function public.cancel_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
  v_game text;
  v_timeout interval;
  v_player record;
  v_balance bigint;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  select * into v_round from public.rounds where id = p_round_id for update;
  if not found then
    raise exception 'La ronda no existe' using errcode = 'P0013';
  end if;
  if not exists (select 1 from public.round_players
                 where round_id = p_round_id and user_id = v_uid) then
    raise exception 'No participas en esta ronda' using errcode = 'P0014';
  end if;
  if v_round.status <> 'in_progress' then
    return jsonb_build_object('round_id', p_round_id, 'status', v_round.status);
  end if;

  select game into v_game from public.tables where id = v_round.table_id;
  if v_game = 'blackjack'
     and exists (select 1 from public.round_players
                  where round_id = p_round_id
                    and (stood or result is not null or cardinality(cards) > 2)) then
    raise exception 'La mano ya está en juego: no se puede cancelar' using errcode = 'P0016';
  end if;

  v_timeout := make_interval(secs => public.config_int('round_timeout_seconds')::int);
  if v_round.created_at + v_timeout > now() then
    raise exception 'La ronda aún no ha superado el tiempo de espera' using errcode = 'P0015';
  end if;

  for v_player in
    select rp.user_id, rp.bet_amount from public.round_players rp
     where rp.round_id = p_round_id order by rp.user_id
  loop
    update public.wallets
       set balance = balance + v_player.bet_amount, updated_at = now()
     where user_id = v_player.user_id
    returning balance into v_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_player.user_id, 'refund', v_player.bet_amount, v_balance, p_round_id,
            'refund:' || p_round_id::text || ':' || v_player.user_id::text)
    on conflict (idempotency_key) do nothing;
  end loop;

  update public.rounds set status = 'cancelled', finished_at = now() where id = p_round_id;
  update public.tables set status = 'open' where id = v_round.table_id;
  return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled', 'reason', 'timeout');
end;
$$;

-- ----------------------------------------------------------------
-- Seeds: mesas de blackjack con apuesta variable y fondo de la banca
-- ----------------------------------------------------------------
insert into public.tables (name, bet_amount, max_players, game, max_bet) values
  ('Blackjack Bronce',   10,  6, 'blackjack', 100),
  ('Blackjack Plata',    50,  6, 'blackjack', 500),
  ('Blackjack Oro',      100, 5, 'blackjack', 1000),
  ('Blackjack Diamante', 500, 4, 'blackjack', 5000);

-- Fondo inicial de la banca (liquidez para pagar premios).
-- Asiento 'adjustment' sin usuario: financiación transparente y auditable.
update public.house_account set balance = balance + 10000000, updated_at = now() where id = true;
insert into public.ledger (user_id, type, amount, balance_after, idempotency_key)
values (null, 'adjustment', 10000000, null, 'house-seed-initial');

revoke all on function public.set_bet(uuid, bigint) from public, anon;
revoke all on function public.bj_action(uuid, text) from public, anon;
grant execute on function public.set_bet(uuid, bigint) to authenticated;
grant execute on function public.bj_action(uuid, text) to authenticated;
revoke all on function public.card_value(smallint) from public, anon, authenticated;
revoke all on function public.hand_value(smallint[]) from public, anon, authenticated;
revoke all on function public.is_blackjack(smallint[]) from public, anon, authenticated;
