-- =============================================================
-- Fase 11 · Blackjack completo:
--   · Doblar (double): x2 apuesta, una carta y plantarse.
--   · Separar (split): dos manos si el par inicial tiene mismo valor.
--   · Seguro (insurance): si la banca enseña A, asegura bet/2 → paga 2:1.
--   · Carta oculta de la banca: la UI solo revela la primera hasta el
--     final (servidor manda; ver README).
--   · cancel_stale_rounds(): limpieza automática por pg_cron.
--
-- Cambio estructural: un jugador puede tener VARIAS manos en una
-- ronda (split) => PK de round_players pasa a (round_id,user_id,hand_no).
-- =============================================================

alter table public.round_players
  add column hand_no smallint not null default 1,
  add column insurance bigint check (insurance is null or insurance > 0);

alter table public.round_players drop constraint round_players_pkey;
alter table public.round_players
  add primary key (round_id, user_id, hand_no);

-- ----------------------------------------------------------------
-- bj_action completo: hit | stand | double | insurance | split
-- (reemplaza a la versión de dos argumentos de la Fase 10)
-- ----------------------------------------------------------------
drop function if exists public.bj_action(uuid, text);
-- ----------------------------------------------------------------
create or replace function public.bj_action(p_round_id uuid, p_action text, p_hand smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
  v_game text;
  v_my public.round_players%rowtype;
  v_ins bigint;
  v_balance bigint;
  v_new_cards smallint[];
  v_dealer_cards smallint[];
  v_dealer_value int;
  v_dealer_natural boolean;
  v_player record;
  v_pv int;
  v_natural boolean;
  v_result_txt text;
  v_winnings bigint;
  v_hole_cards smallint[];
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;
  if p_action not in ('hit','stand','double','insurance','split') then
    raise exception 'Acción inválida' using errcode = 'P0019';
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

  -- --------------------------------------------------------------
  -- SEGURO: solo antes de actuar, con la banca mostrando un as
  -- --------------------------------------------------------------
  if p_action = 'insurance' then
    select * into v_my from public.round_players
     where round_id = p_round_id and user_id = v_uid and hand_no = 1 for update;
    if not found then
      raise exception 'No participas en esta ronda' using errcode = 'P0014';
    end if;
    if v_my.insurance is not null then
      return jsonb_build_object('round_id', p_round_id, 'status', 'already_insured');
    end if;
    if v_my.stood or cardinality(v_my.cards) <> 2 then
      raise exception 'El seguro solo se puede tomar antes de jugar tu mano' using errcode = 'P0020';
    end if;
    if public.card_rank(v_round.dealer_cards[1]) <> 14 then
      raise exception 'El seguro solo es posible si la banca muestra un As' using errcode = 'P0021';
    end if;

    v_ins := v_my.bet_amount / 2;
    update public.wallets set balance = balance - v_ins, updated_at = now()
     where user_id = v_uid and balance >= v_ins
    returning balance into v_balance;
    if not found then
      raise exception 'Saldo insuficiente para el seguro' using errcode = 'P0009';
    end if;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_uid, 'bet_lock', -v_ins, v_balance, p_round_id,
            'bjins:' || p_round_id::text || ':' || v_uid::text)
    on conflict (idempotency_key) do nothing;
    update public.round_players set insurance = v_ins
     where round_id = p_round_id and user_id = v_uid and hand_no = 1;
    return jsonb_build_object('round_id', p_round_id, 'status', 'insured', 'insurance', v_ins);
  end if;

  -- --------------------------------------------------------------
  -- SEPARAR: par inicial -> dos manos, cada una con su apuesta
  -- --------------------------------------------------------------
  if p_action = 'split' then
    select * into v_my from public.round_players
     where round_id = p_round_id and user_id = v_uid and hand_no = 1 for update;
    if not found then
      raise exception 'No participas en esta ronda' using errcode = 'P0014';
    end if;
    if v_my.stood or cardinality(v_my.cards) <> 2
       or public.card_rank(v_my.cards[1]) <> public.card_rank(v_my.cards[2]) then
      raise exception 'Solo puedes separar un par inicial' using errcode = 'P0022';
    end if;
    if exists (select 1 from public.round_players
               where round_id = p_round_id and user_id = v_uid and hand_no = 2) then
      return jsonb_build_object('round_id', p_round_id, 'status', 'already_split');
    end if;
    if v_my.insurance is not null then
      raise exception 'No puedes separar tras asegurar' using errcode = 'P0020';
    end if;

    -- Segunda apuesta igual a la primera
    update public.wallets set balance = balance - v_my.bet_amount, updated_at = now()
     where user_id = v_uid and balance >= v_my.bet_amount
    returning balance into v_balance;
    if not found then
      raise exception 'Saldo insuficiente para separar' using errcode = 'P0009';
    end if;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_uid, 'bet_lock', -v_my.bet_amount, v_balance, p_round_id,
            'bet:' || p_round_id::text || ':' || v_uid::text || ':h2')
    on conflict (idempotency_key) do nothing;

    v_new_cards := array[v_my.cards[1], public.draw_card(p_round_id)];
    update public.round_players set cards = v_new_cards
     where round_id = p_round_id and user_id = v_uid and hand_no = 1;
    -- La segunda mano recibe la otra carta original y una nueva (sin repetición)
    insert into public.round_players (round_id, user_id, hand_no, bet_amount, cards)
    values (p_round_id, v_uid, 2, v_my.bet_amount, array[v_my.cards[2]]);
    update public.round_players set cards = cards || public.draw_card(p_round_id)
     where round_id = p_round_id and user_id = v_uid and hand_no = 2;

    update public.rounds set pot = pot + v_my.bet_amount where id = p_round_id;
    return jsonb_build_object('round_id', p_round_id, 'status', 'split');
  end if;

  -- --------------------------------------------------------------
  -- hit / stand / double sobre una mano concreta
  -- --------------------------------------------------------------
  select * into v_my from public.round_players
   where round_id = p_round_id and user_id = v_uid and hand_no = p_hand for update;
  if not found then
    raise exception 'No tienes esa mano en la ronda' using errcode = 'P0014';
  end if;
  if v_my.stood then
    return jsonb_build_object('round_id', p_round_id, 'status', 'already_stood');
  end if;

  if p_action = 'double' then
    if cardinality(v_my.cards) <> 2 then
      raise exception 'Solo puedes doblar con tus dos primeras cartas' using errcode = 'P0023';
    end if;
    update public.wallets set balance = balance - v_my.bet_amount, updated_at = now()
     where user_id = v_uid and balance >= v_my.bet_amount
    returning balance into v_balance;
    if not found then
      raise exception 'Saldo insuficiente para doblar' using errcode = 'P0009';
    end if;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_uid, 'bet_lock', -v_my.bet_amount, v_balance, p_round_id,
            'bet2:' || p_round_id::text || ':' || v_uid::text || ':h' || p_hand::text)
    on conflict (idempotency_key) do nothing;
    update public.round_players set bet_amount = bet_amount * 2
     where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
    update public.rounds set pot = pot + v_my.bet_amount where id = p_round_id;

    update public.round_players set cards = cards || public.draw_card(p_round_id)
     where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
    if (select public.hand_value(cards) from public.round_players
         where round_id = p_round_id and user_id = v_uid and hand_no = p_hand) > 21 then
      update public.round_players set stood = true, result = 'loss'
       where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
    else
      update public.round_players set stood = true
       where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
    end if;
  elsif p_action = 'hit' then
    update public.round_players set cards = cards || public.draw_card(p_round_id)
     where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
    if (select public.hand_value(cards) from public.round_players
         where round_id = p_round_id and user_id = v_uid and hand_no = p_hand) > 21 then
      update public.round_players set stood = true, result = 'loss'
       where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
    end if;
  else
    update public.round_players set stood = true
     where round_id = p_round_id and user_id = v_uid and hand_no = p_hand;
  end if;

  -- --------------------------------------------------------------
  -- ¿Mano/ronda terminada? La banca juega y se liquida todo.
  -- --------------------------------------------------------------
  if exists (select 1 from public.round_players
             where round_id = p_round_id and not stood) then
    return jsonb_build_object('round_id', p_round_id, 'status', 'playing');
  end if;

  v_dealer_cards := v_round.dealer_cards;
  -- Revelar la carta oculta de la banca (inaccesible desde la API)
  select h.cards into v_hole_cards from public.round_dealer_holes h
   where h.round_id = p_round_id;
  if v_hole_cards is not null then
    v_dealer_cards := v_dealer_cards || v_hole_cards;
    delete from public.round_dealer_holes where round_id = p_round_id;
  end if;
  while public.hand_value(v_dealer_cards) < 17 loop
    v_dealer_cards := v_dealer_cards || public.draw_card(p_round_id);
  end loop;
  update public.rounds set dealer_cards = v_dealer_cards where id = p_round_id;
  v_dealer_value := public.hand_value(v_dealer_cards);
  v_dealer_natural := public.is_blackjack(v_dealer_cards);

  for v_player in
    select rp.user_id, rp.hand_no, rp.bet_amount, rp.insurance, rp.cards, rp.result
      from public.round_players rp where rp.round_id = p_round_id
     order by rp.user_id, rp.hand_no
  loop
    -- Resolver resultado de la mano si está pendiente
    if v_player.result is null then
      v_pv := public.hand_value(v_player.cards);
      -- Blackjack natural solo con la mano inicial (no tras separar)
      v_natural := public.is_blackjack(v_player.cards) and v_player.hand_no = 1;
      update public.round_players
         set result = case
           when v_dealer_value > 21 then 'win'
           when v_natural and not v_dealer_natural then 'blackjack'
           when v_dealer_natural and not v_natural then 'loss'
           when v_natural and v_dealer_natural then 'push'
           when v_pv > v_dealer_value then 'win'
           when v_pv = v_dealer_value then 'push'
           else 'loss'
         end
       where round_id = p_round_id and user_id = v_player.user_id and hand_no = v_player.hand_no
      returning result into v_result_txt;
      v_player.result := v_result_txt;
    end if;

    -- Contabilidad por mano (cuadra a 0 con bet_lock):
    --   stake siempre a la casa; refund/payout y su espejo a la casa.
    update public.house_account
       set balance = balance + v_player.bet_amount, updated_at = now() where id = true;
    insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
    values (null, 'house_settlement', v_player.bet_amount, p_round_id,
            'bjstake:' || p_round_id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
    on conflict (idempotency_key) do nothing;

    if v_player.result = 'push' then
      update public.wallets set balance = balance + v_player.bet_amount, updated_at = now()
       where user_id = v_player.user_id returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
      values (v_player.user_id, 'refund', v_player.bet_amount, v_balance, p_round_id,
              'bjpush:' || p_round_id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
      on conflict (idempotency_key) do nothing;
      update public.house_account
         set balance = balance - v_player.bet_amount, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
      values (null, 'house_settlement', -v_player.bet_amount, p_round_id,
              'bjhouserefund:' || p_round_id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
      on conflict (idempotency_key) do nothing;
    elsif v_player.result in ('win','blackjack') then
      v_winnings := case when v_player.result = 'blackjack'
                         then v_player.bet_amount + (v_player.bet_amount * 3 + 1) / 2
                         else v_player.bet_amount * 2 end;
      update public.wallets set balance = balance + v_winnings, updated_at = now()
       where user_id = v_player.user_id returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
      values (v_player.user_id, 'payout', v_winnings, v_balance, p_round_id,
              'bjpay:' || p_round_id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
      on conflict (idempotency_key) do nothing;
      update public.house_account
         set balance = balance - v_winnings, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
      values (null, 'house_settlement', -v_winnings, p_round_id,
              'bjhouseloss:' || p_round_id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
      on conflict (idempotency_key) do nothing;
    end if;

    -- Seguro (una vez por jugador, solo mano 1): la casa cobra el seguro
    -- y, si tenía blackjack natural, paga 2:1 (3× total al jugador).
    if v_player.hand_no = 1 and v_player.insurance is not null then
      update public.house_account
         set balance = balance + v_player.insurance, updated_at = now() where id = true;
      insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
      values (null, 'house_settlement', v_player.insurance, p_round_id,
              'bjinsstake:' || p_round_id::text || ':' || v_player.user_id::text)
      on conflict (idempotency_key) do nothing;

      if v_dealer_natural then
        v_winnings := v_player.insurance * 3;
        update public.wallets set balance = balance + v_winnings, updated_at = now()
         where user_id = v_player.user_id returning balance into v_balance;
        insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
        values (v_player.user_id, 'payout', v_winnings, v_balance, p_round_id,
                'bjinspay:' || p_round_id::text || ':' || v_player.user_id::text)
        on conflict (idempotency_key) do nothing;
        update public.house_account
           set balance = balance - v_winnings, updated_at = now() where id = true;
        insert into public.ledger (user_id, type, amount, round_id, idempotency_key)
        values (null, 'house_settlement', -v_winnings, p_round_id,
                'bjinshouse:' || p_round_id::text || ':' || v_player.user_id::text)
        on conflict (idempotency_key) do nothing;
      end if;
    end if;
  end loop;

  update public.rounds set status = 'finished', finished_at = now() where id = p_round_id;
  update public.tables set status = 'open' where id = v_round.table_id;
  return jsonb_build_object('round_id', p_round_id, 'status', 'finished');
end;
$$;

-- =============================================================
-- cancel_round revisado: en blackjack no se cancela si alguien
-- actuó (incluye seguro); basta con el timeout en mesas quietas.
-- =============================================================
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
                    and (stood or result is not null or cardinality(cards) > 2
                         or insurance is not null)) then
    raise exception 'La mano ya está en juego: no se puede cancelar' using errcode = 'P0016';
  end if;

  v_timeout := make_interval(secs => public.config_int('round_timeout_seconds')::int);
  if v_round.created_at + v_timeout > now() then
    raise exception 'La ronda aún no ha superado el tiempo de espera' using errcode = 'P0015';
  end if;

  for v_player in
    select rp.user_id, rp.hand_no, rp.bet_amount, rp.insurance from public.round_players rp
     where rp.round_id = p_round_id order by rp.user_id, rp.hand_no
  loop
    update public.wallets
       set balance = balance + v_player.bet_amount + coalesce(v_player.insurance, 0),
           updated_at = now()
     where user_id = v_player.user_id
    returning balance into v_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_player.user_id, 'refund', v_player.bet_amount + coalesce(v_player.insurance, 0),
            v_balance, p_round_id,
            'refund:' || p_round_id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
    on conflict (idempotency_key) do nothing;
  end loop;

  update public.rounds set status = 'cancelled', finished_at = now() where id = p_round_id;
  delete from public.round_dealer_holes where round_id = p_round_id;
  update public.tables set status = 'open' where id = v_round.table_id;
  return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled', 'reason', 'timeout');
end;
$$;

-- =============================================================
-- Limpieza automática: cancela (reembolsando) rondas atascadas.
-- Sin jugador autenticado -> solo desde cron (sin EXECUTE público).
-- =============================================================
create or replace function public.cancel_stale_rounds()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round record;
  v_player record;
  v_balance bigint;
  v_timeout interval;
  v_count int := 0;
begin
  v_timeout := make_interval(secs => public.config_int('round_timeout_seconds')::int);

  for v_round in
    select r.* from public.rounds r
     where r.status = 'in_progress' and r.created_at + v_timeout <= now()
       and not exists (
         select 1 from public.round_players rp
          where rp.round_id = r.id
            and (rp.stood or rp.result is not null or cardinality(rp.cards) > 2
                 or rp.insurance is not null))
  loop
    for v_player in
      select rp.user_id, rp.hand_no, rp.bet_amount, rp.insurance
        from public.round_players rp where rp.round_id = v_round.id
       order by rp.user_id, rp.hand_no
    loop
      update public.wallets
         set balance = balance + v_player.bet_amount + coalesce(v_player.insurance, 0),
             updated_at = now()
       where user_id = v_player.user_id
      returning balance into v_balance;
      insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
      values (v_player.user_id, 'refund', v_player.bet_amount + coalesce(v_player.insurance, 0),
              v_balance, v_round.id,
              'refund:' || v_round.id::text || ':' || v_player.user_id::text || ':h' || v_player.hand_no::text)
      on conflict (idempotency_key) do nothing;
    end loop;

    update public.rounds set status = 'cancelled', finished_at = now() where id = v_round.id;
    delete from public.round_dealer_holes where round_id = v_round.id;
    update public.tables set status = 'open' where id = v_round.table_id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Idempotency note: para blackjack se añadió ':hX' en split/double; la
-- limpieza por cron usa las claves base (cubre rondas sin actuar, que
-- nunca tienen split/double/insurance).

revoke all on function public.cancel_stale_rounds() from public, anon, authenticated;

-- Programación con pg_cron si está disponible; si no, se puede llamar
-- periódicamente desde un cron externo (GitHub Actions, etc.).
do $$
begin
  create extension if not exists pg_cron with schema extensions;
exception when others then
  raise notice 'pg_cron no disponible: programa cancel_stale_rounds manualmente';
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('cancel-stale-rounds', '*/5 * * * *',
                          $cron$select public.cancel_stale_rounds()$cron$);
  end if;
end $$;

grant execute on function public.bj_action(uuid, text, smallint) to authenticated;
