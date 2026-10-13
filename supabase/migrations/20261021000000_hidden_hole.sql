-- =============================================================
-- Fase 13 · Carta oculta REAL de la banca + avatares
--
--  * round_dealer_holes: tabla sin permisos de lectura para la API
--    (RLS sin policy + sin GRANT). Solo las funciones SECURITY
--    DEFINER la tocan. Así ni el SELECT ni Realtime filtran el hueco.
--  * draw_card también excluye las cartas ocultas (sin repetición).
--  * start_round reparte 1 carta visible + 1 oculta a la banca; al
--    liquidar la ronda se funden en rounds.dealer_cards.
--  * Avatares: emoji en profiles.avatar_url (edición ya permitida
--    por privilegio de columna). Sin storage.
-- =============================================================

create table public.round_dealer_holes (
  round_id uuid primary key references public.rounds (id) on delete cascade,
  cards smallint[] not null check (cardinality(cards) >= 1)
);

alter table public.round_dealer_holes enable row level security;
-- Sin ninguna policy: nadie lee/escribe vía API (las funciones definer
-- ignoran RLS). La tabla tampoco está publicada en Realtime.
revoke all on public.round_dealer_holes from anon, authenticated;

-- Fix de Fase 13: los GRANT por defecto de Supabase daban UPDATE
-- completo de profiles a authenticated; lo reducimos al avatar.
revoke update on public.profiles from authenticated;
grant update (avatar_url) on public.profiles to authenticated;


-- draw_card excluye también la carta oculta de la banca
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
      union all
      select unnest(h.cards) from public.round_dealer_holes h where h.round_id = p_round
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

-- start_round: blackjack reparte 1 carta visible + 1 OCULTA a la banca
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

    -- Reparto: 2 cartas por jugador (en dos pasos para no repetir)…
    update public.round_players set cards = array[public.draw_card(v_round_id)]
     where round_id = v_round_id;
    update public.round_players set cards = cards || public.draw_card(v_round_id)
     where round_id = v_round_id;
    -- …y la banca: 1 visible + 1 OCULTA (inaccesible desde la API)
    update public.rounds
       set dealer_cards = array[public.draw_card(v_round_id)], pot = v_pot
     where id = v_round_id;
    insert into public.round_dealer_holes (round_id, cards)
    values (v_round_id, array[public.draw_card(v_round_id)]);

    update public.table_players set pending_bet = null
     where table_id = p_table_id;
    update public.tables set status = 'in_round' where id = p_table_id;
    return jsonb_build_object('round_id', v_round_id, 'pot', v_pot, 'players', v_seated);
  end if;

  -- Dados / Póker (igual que antes)
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
