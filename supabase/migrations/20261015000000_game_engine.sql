-- =============================================================
-- Fase 5 · Motor de juego (TODO en el servidor)
--
--  * Dados criptográficos: pgcrypto.gen_random_bytes con muestreo
--    SIN SESGO (rejection sampling). Jamás se usa random().
--  * Todo movimiento de fichas en una sola transacción por ronda,
--    con claves de idempotencia: una ronda no puede pagar dos veces
--    aunque se llame dos veces a roll_round.
--  * El ledger de cada ronda cuadra a 0:
--      sum(bet_lock) + payout + house_fee + refunds = 0
-- =============================================================

alter table public.rounds
  add column tiebreak_round smallint not null default 0;

insert into public.config (key, value, description) values
  ('round_timeout_seconds', '300', 'Tiempo máx. de una ronda sin terminar antes de poder cancelarse con reembolso');

-- -------------------------------------------------------------
-- Dado criptográfico sin sesgo (interno, NO expuesto a la API).
-- Rejection sampling: bytes 0..251 (252 = 42·6), se rechazan 252..255
-- para que cada cara tenga exactamente 1/6 de probabilidad.
-- -------------------------------------------------------------
create or replace function public.roll_d6()
returns smallint
language plpgsql
volatile
set search_path = public
as $$
declare
  v_byte int;
begin
  loop
    v_byte := get_byte(extensions.gen_random_bytes(1), 0);
    if v_byte < 252 then
      return (v_byte % 6 + 1)::smallint;
    end if;
  end loop;
end;
$$;

revoke all on function public.roll_d6() from public, anon, authenticated;

-- -------------------------------------------------------------
-- start_round: crea la ronda, bloquea las apuestas de TODOS los
-- sentados y pasa la mesa a 'in_round' — todo en una transacción.
-- -------------------------------------------------------------
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

  -- Bloquear la mesa: solo UNA ronda arranca a la vez
  select * into v_table from public.tables where id = p_table_id for update;
  if not found then
    raise exception 'La mesa no existe' using errcode = 'P0004';
  end if;
  if v_table.status <> 'open' then
    raise exception 'La mesa ya tiene una ronda en curso' using errcode = 'P0005';
  end if;

  -- El que arranca debe estar sentado (pertenencia)
  if not exists (select 1 from public.table_players
                 where table_id = p_table_id and user_id = v_uid and status = 'seated') then
    raise exception 'No estás sentado en esta mesa' using errcode = 'P0010';
  end if;

  -- Mínimo de jugadores
  v_min := public.config_int('min_players')::int;
  select count(*) into v_seated from public.table_players
   where table_id = p_table_id and status = 'seated';
  if v_seated < v_min then
    raise exception 'Se necesitan al menos % jugadores (hay %)', v_min, v_seated
      using errcode = 'P0012';
  end if;

  -- Crear la ronda y apuntar a todos los sentados
  insert into public.rounds (table_id, status)
  values (p_table_id, 'in_progress')
  returning id into v_round_id;

  insert into public.round_players (round_id, user_id, bet_amount)
  select v_round_id, user_id, v_table.bet_amount
    from public.table_players
   where table_id = p_table_id and status = 'seated';

  -- Bloquear apuestas: wallets bloqueadas EN ORDEN de user_id para
  -- evitar deadlocks entre rondas concurrentes del mismo jugador.
  v_pot := 0;
  for v_player in
    select rp.user_id, rp.bet_amount
      from public.round_players rp
     where rp.round_id = v_round_id
     order by rp.user_id
  loop
    update public.wallets
       set balance = balance - v_player.bet_amount,
           updated_at = now()
     where user_id = v_player.user_id and balance >= v_player.bet_amount
    returning balance into v_balance;

    if not found then
      -- CHECK(balance>=0) también lo forzaría, pero damos mensaje claro;
      -- al lanzar la excepción, TODA la transacción se revierte.
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

-- -------------------------------------------------------------
-- roll_round: el jugador autenticado lanza SUS dados. Cuando
-- todos han lanzado, se resuelve la ronda aquí mismo:
--   · ganador único  -> payout + house_fee, ronda finished
--   · empate         -> re-lanzan solo los empatados (máx
--                       max_tiebreaks); si persiste -> refund a todos
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
  v_max_tiebreaks int;
  v_all_rolled boolean;
  v_max_total smallint;
  v_winners uuid[];
  v_winner uuid;
  v_fee_pct bigint;
  v_fee bigint;
  v_prize bigint;
  v_balance bigint;
  v_player record;
  v_house_balance bigint;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  -- Bloqueo de la ronda: llamadas concurrentes se serializan aquí
  select * into v_round from public.rounds where id = p_round_id for update;
  if not found then
    raise exception 'La ronda no existe' using errcode = 'P0013';
  end if;
  if v_round.status <> 'in_progress' then
    -- Idempotente: una ronda ya resuelta devuelve su estado actual
    return jsonb_build_object('round_id', p_round_id, 'status', v_round.status,
                              'winner_id', v_round.winner_id);
  end if;

  -- Pertencia: el jugador debe participar en la ronda
  if not exists (select 1 from public.round_players
                 where round_id = p_round_id and user_id = v_uid) then
    raise exception 'No participas en esta ronda' using errcode = 'P0014';
  end if;

  -- 1. Lanzar los dados del jugador que llama (si aún no lanzó).
  --    La generación es irrepetible desde el rol authenticated:
  --    solo esta función (SECURITY DEFINER) puede escribir dice1/dice2.
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

  -- 2. ¿Han lanzado ya todos?
  select not exists (select 1 from public.round_players
                     where round_id = p_round_id and dice1 is null)
    into v_all_rolled;
  if not v_all_rolled then
    return jsonb_build_object('round_id', p_round_id, 'status', 'waiting_rolls');
  end if;

  -- 3. Resolver: total más alto
  select max(rp.total) into v_max_total
    from public.round_players rp where rp.round_id = p_round_id;

  select array_agg(rp.user_id) into v_winners
    from public.round_players rp
   where rp.round_id = p_round_id and rp.total = v_max_total;

  v_max_tiebreaks := public.config_int('max_tiebreaks')::int;
  v_fee_pct := public.config_int('house_fee_percent');

  -- 4a. Ganador único + empate definitivo (sin más desempates)
  if cardinality(v_winners) = 1 or v_round.tiebreak_round >= v_max_tiebreaks then
    -- 4b. Empate persistente tras agotar desempates: refund a TODOS, sin comisión
    if cardinality(v_winners) > 1 then
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

      update public.rounds
         set status = 'cancelled', finished_at = now()
       where id = p_round_id;
      update public.tables set status = 'open' where id = v_round.table_id;

      return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled',
                                'reason', 'tiebreak_exhausted');
    end if;

    -- Hay UN ganador
    v_winner := v_winners[1];

    -- Comisión: floor(pozo * % / 100). El redondeo (hacia abajo)
    -- favorece SIEMPRE al jugador: casa + payout suman exactamente el pozo.
    v_fee   := floor(v_round.pot * v_fee_pct::numeric / 100)::bigint;
    v_prize := v_round.pot - v_fee;

    -- Payout al ganador
    update public.wallets
       set balance = balance + v_prize, updated_at = now()
     where user_id = v_winner
    returning balance into v_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (v_winner, 'payout', v_prize, v_balance, p_round_id,
            'payout:' || p_round_id::text)
    on conflict (idempotency_key) do nothing;

    -- Comisión a la casa (user_id NULL + balance_after NULL)
    update public.house_account
       set balance = balance + v_fee, updated_at = now()
     where id = true
    returning balance into v_house_balance;
    insert into public.ledger (user_id, type, amount, balance_after, round_id, idempotency_key)
    values (null, 'house_fee', v_fee, null, p_round_id,
            'housefee:' || p_round_id::text)
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

  -- 5. Empate, quedan desempates: solo los empatados re-lanzan
  update public.rounds
     set tiebreak_round = tiebreak_round + 1
   where id = p_round_id;
  update public.round_players
     set dice1 = null, dice2 = null
   where round_id = p_round_id and user_id = any (v_winners);

  return jsonb_build_object('round_id', p_round_id, 'status', 'tiebreak',
                            'tied_players', v_winners,
                            'tiebreak_round', v_round.tiebreak_round + 1);
end;
$$;

-- -------------------------------------------------------------
-- cancel_round: red de seguridad por desconexiones. Solo si la
-- ronda lleva más de round_timeout_seconds sin terminar.
-- Devuelve las apuestas (refund) sin comisión. Idempotente.
-- -------------------------------------------------------------
create or replace function public.cancel_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_round public.rounds%rowtype;
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

  v_timeout := make_interval(secs => public.config_int('round_timeout_seconds')::int);
  if v_round.created_at + v_timeout > now() then
    raise exception 'La ronda aún no ha superado el tiempo de espera' using errcode = 'P0015';
  end if;

  -- Reembolso completo a todos (sin comisión)
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

  update public.rounds
     set status = 'cancelled', finished_at = now()
   where id = p_round_id;
  update public.tables set status = 'open' where id = v_round.table_id;

  return jsonb_build_object('round_id', p_round_id, 'status', 'cancelled', 'reason', 'timeout');
end;
$$;

-- -------------------------------------------------------------
-- get_leaderboard: ranking por fichas ganadas en payouts.
-- -------------------------------------------------------------
create or replace function public.get_leaderboard(p_limit int default 10)
returns table (username text, rounds_won bigint, total_won bigint)
language sql
stable
security definer
set search_path = public
as $$
  select pr.username,
         count(*) filter (where rp.is_winner) as rounds_won,
         coalesce(sum(l.amount) filter (where l.type = 'payout'), 0) as total_won
    from public.profiles pr
    left join public.round_players rp on rp.user_id = pr.id
    left join public.ledger l on l.user_id = pr.id and l.type = 'payout'
   group by pr.id, pr.username
   order by total_won desc, rounds_won desc, pr.username
   limit greatest(1, least(p_limit, 100));
$$;

-- Permisos: solo authenticated ejecuta las RPC públicas;
-- roll_d6 es interna (ya revocada arriba).
revoke all on function public.start_round(uuid) from public, anon;
revoke all on function public.roll_round(uuid) from public, anon;
revoke all on function public.cancel_round(uuid) from public, anon;
revoke all on function public.get_leaderboard(int) from public, anon;
grant execute on function public.start_round(uuid) to authenticated;
grant execute on function public.roll_round(uuid) to authenticated;
grant execute on function public.cancel_round(uuid) to authenticated;
grant execute on function public.get_leaderboard(int) to authenticated;
