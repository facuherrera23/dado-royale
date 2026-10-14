-- =============================================================
-- Fase 9 · Póker de 2 cartas
--
--  * Nueva columna tables.game ('dice' | 'poker').
--  * Cartas como enteros 1..52: palo = (c-1)/4... no: índice único,
--    valor = ((c-1) % 13) + 2  (2..14, A=14), palo = (c-1)/13 (0..3).
--  * draw_card: reparte una carta SIN REPETICIÓN de entre las no
--    repartidas de la ronda, con muestreo uniforme criptográfico
--    (rejection sampling sobre gen_random_bytes, nunca random()).
--  * roll_round se generaliza: mesas 'dice' tiran dados, mesas
--    'poker' reparten las 2 cartas del jugador que llama. Al
--    completar todos, gana la mejor mano; empate -> solo los
--    empatados reciben cartas nuevas (máx max_tiebreaks), si
--    persiste -> refund sin comisión. Pozo/comisión/reembolso
--    e idempotencia son idénticos a los dados.
-- =============================================================

alter table public.tables
  add column game text not null default 'dice' check (game in ('dice','poker'));

alter table public.round_players
  add column card1 smallint check (card1 between 1 and 52),
  add column card2 smallint check (card2 between 1 and 52);

insert into public.tables (name, bet_amount, max_players, game) values
  ('Póker Bronce',   10,  6, 'poker'),
  ('Póker Plata',    50,  6, 'poker'),
  ('Póker Oro',      100, 5, 'poker'),
  ('Póker Diamante', 500, 4, 'poker');

-- -------------------------------------------------------------
-- _uniform(p_max): entero uniforme en 1..p_max con bytes de
-- pgcrypto y rejection sampling (sin sesgo). Interna.
-- -------------------------------------------------------------
create or replace function public._uniform(p_max int)
returns int
language plpgsql
volatile
set search_path = public
as $$
declare
  v_byte int;
  v_accept int;
begin
  if p_max is null or p_max < 1 then
    raise exception 'p_max inválido' using errcode = 'P0050';
  end if;
  v_accept := p_max * (256 / p_max); -- múltiplo de p_max más cercano a 256
  loop
    v_byte := get_byte(extensions.gen_random_bytes(1), 0);
    if v_byte < v_accept then
      return v_byte % p_max + 1;
    end if;
  end loop;
end;
$$;

-- -------------------------------------------------------------
-- draw_card(p_round): una carta al azar de las NO repartidas en
-- la ronda (baraja única por ronda, sin repetición). Interna.
-- -------------------------------------------------------------
create or replace function public.draw_card(p_round uuid)
returns smallint
language plpgsql
volatile
set search_path = public
as $$
declare
  v_remaining smallint[];
  v_idx int;
begin
  v_remaining := array(
    select c::smallint
      from generate_series(1, 52) as g(c)
     where c::smallint <> all (
       coalesce((select array_agg(card1) from public.round_players
                  where round_id = p_round and card1 is not null), '{}'::smallint[])
       ||
       coalesce((select array_agg(card2) from public.round_players
                  where round_id = p_round and card2 is not null), '{}'::smallint[])
     )
  );
  if array_length(v_remaining, 1) is null then
    raise exception 'No quedan cartas en la baraja' using errcode = 'P0051';
  end if;
  v_idx := public._uniform(array_length(v_remaining, 1));
  return v_remaining[v_idx];
end;
$$;

-- -------------------------------------------------------------
-- card_rank: valor de una carta 1..52 -> 2..14 (A=14)
-- hand_score: mano de 2 cartas -> puntuación totalmente ordenable
--   pareja: 10000 + valor ; carta alta: mayor*100 + menor
-- -------------------------------------------------------------
create or replace function public.card_rank(p_card smallint)
returns smallint
language sql
immutable
set search_path = public
as $$
  select ((p_card - 1) % 13 + 2)::smallint;
$$;

create or replace function public.hand_score(p_c1 smallint, p_c2 smallint)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    when p_c1 is null or p_c2 is null then 0
    when public.card_rank(p_c1) = public.card_rank(p_c2)
      then 10000 + public.card_rank(p_c1)::int
    else greatest(public.card_rank(p_c1), public.card_rank(p_c2))::int * 100
         + least(public.card_rank(p_c1), public.card_rank(p_c2))::int
  end;
$$;

-- -------------------------------------------------------------
-- roll_round: versión con soporte póker (reemplaza la de dados).
-- -------------------------------------------------------------
create or replace function public.roll_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
  v_game text;
  v_max_tiebreaks int;
  v_all_rolled boolean;
  v_winners uuid[];
  v_winner uuid;
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

  select game into v_game from public.tables where id = v_round.table_id;

  -- 1. Acción del jugador que llama (idempotente por jugador)
  if v_game = 'poker' then
    update public.round_players
       set card1 = public.draw_card(p_round_id)
     where round_id = p_round_id and user_id = v_uid and card1 is null;
    update public.round_players
       set card2 = public.draw_card(p_round_id),
           tiebreak_attempts = v_round.tiebreak_round
     where round_id = p_round_id and user_id = v_uid and card2 is null;
    perform public.log_round_event(p_round_id, 'dealt',
      (select jsonb_build_object('user_id', v_uid, 'card1', rp.card1, 'card2', rp.card2)
         from public.round_players rp
        where rp.round_id = p_round_id and rp.user_id = v_uid));

    select not exists (select 1 from public.round_players
                       where round_id = p_round_id and card1 is null)
      into v_all_rolled;
  else
    update public.round_players
       set dice1 = public.roll_d6(),
           dice2 = public.roll_d6(),
           tiebreak_attempts = v_round.tiebreak_round
     where round_id = p_round_id and user_id = v_uid and dice1 is null;
    if found then
      perform public.log_round_event(p_round_id, 'rolled',
        (select jsonb_build_object('user_id', v_uid, 'dice1', rp.dice1, 'dice2', rp.dice2)
           from public.round_players rp
          where rp.round_id = p_round_id and rp.user_id = v_uid));
    end if;

    select not exists (select 1 from public.round_players
                       where round_id = p_round_id and dice1 is null)
      into v_all_rolled;
  end if;

  if not v_all_rolled then
    return jsonb_build_object('round_id', p_round_id, 'status', 'waiting_rolls');
  end if;

  -- 2. Resolución según el juego
  if v_game = 'poker' then
    select array_agg(rp.user_id) into v_winners
      from public.round_players rp
     where rp.round_id = p_round_id
       and public.hand_score(rp.card1, rp.card2) = (
         select max(public.hand_score(rp2.card1, rp2.card2))
           from public.round_players rp2 where rp2.round_id = p_round_id);
  else
    select array_agg(rp.user_id) into v_winners
      from public.round_players rp
     where rp.round_id = p_round_id
       and rp.total = (select max(rp2.total) from public.round_players rp2
                        where rp2.round_id = p_round_id);
  end if;

  v_max_tiebreaks := public.config_int('max_tiebreaks')::int;
  v_fee_pct := public.config_int('house_fee_percent');

  -- 3a. Ganador único o empate definitivo
  if cardinality(v_winners) = 1 or v_round.tiebreak_round >= v_max_tiebreaks then
    if cardinality(v_winners) > 1 then
      -- Reembolso completo, sin comisión
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
      return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled',
                                'reason', 'tiebreak_exhausted');
    end if;

    v_winner := v_winners[1];
    -- floor(): el redondeo siempre favorece al jugador (fee + payout = pozo)
    v_fee   := floor(v_round.pot * v_fee_pct::numeric / 100)::bigint;
    v_prize := v_round.pot - v_fee;

    update public.wallets
       set balance = balance + v_prize, updated_at = now()
     where user_id = v_winner
    returning balance into v_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_winner, 'payout', v_prize, v_balance, p_round_id, 'payout:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;

    update public.house_account set balance = balance + v_fee, updated_at = now() where id = true;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (null, 'house_fee', v_fee, null, p_round_id, 'housefee:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;

    update public.rounds
       set status = 'finished', winner_id = v_winner, house_fee = v_fee, finished_at = now()
     where id = p_round_id;
    update public.round_players set is_winner = true
     where round_id = p_round_id and user_id = v_winner;
    update public.tables set status = 'open' where id = v_round.table_id;

    perform public.log_round_event(p_round_id, 'finished',
      jsonb_build_object('winner_id', v_winner, 'pot', v_round.pot, 'house_fee', v_fee));

    return jsonb_build_object('round_id', p_round_id, 'status', 'finished',
                              'winner_id', v_winner, 'pot', v_round.pot,
                              'house_fee', v_fee, 'prize', v_prize);
  end if;

  -- 4. Empate con desempates restantes: solo los empatados vuelven a jugar
  update public.rounds set tiebreak_round = tiebreak_round + 1 where id = p_round_id;
  if v_game = 'poker' then
    update public.round_players set card1 = null, card2 = null
     where round_id = p_round_id and user_id = any (v_winners);
  else
    update public.round_players set dice1 = null, dice2 = null
     where round_id = p_round_id and user_id = any (v_winners);
  end if;

  return jsonb_build_object('round_id', p_round_id, 'status', 'tiebreak',
                            'tied_players', v_winners,
                            'tiebreak_round', v_round.tiebreak_round + 1);
end;
$$;

revoke all on function public._uniform(int) from public, anon, authenticated;
revoke all on function public.draw_card(uuid) from public, anon, authenticated;
revoke all on function public.card_rank(smallint) from public, anon, authenticated;
revoke all on function public.hand_score(smallint, smallint) from public, anon, authenticated;
