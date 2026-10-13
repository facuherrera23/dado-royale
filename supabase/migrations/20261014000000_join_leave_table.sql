-- =============================================================
-- Fase 4 · RPC join_table / leave_table
--
--  * El jugador se sienta sin mover fichas todavía: la apuesta se
--    bloquea al unirse a la RONDA (Fase 5). Solo exigimos que
--    tenga saldo suficiente para la apuesta fija de la mesa.
--  * Un jugador solo puede estar sentado en UNA mesa a la vez.
--  * Rate limiting: join_cooldown_seconds entre acciones (unirse/salir).
--  * Concurrencia: bloqueo FOR UPDATE de la fila de la mesa al
--    contar asientos, para no sobrepasar max_players.
-- =============================================================

create or replace function public.join_table(p_table_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_table public.tables%rowtype;
  v_seated int;
  v_cooldown interval;
  v_last_action timestamptz;
  v_balance bigint;
  v_other_table uuid;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  -- La mesa existe y está abierta (bloqueada durante el chequeo de aforo)
  select * into v_table from public.tables where id = p_table_id for update;
  if not found then
    raise exception 'La mesa no existe' using errcode = 'P0004';
  end if;
  if v_table.status <> 'open' then
    raise exception 'La mesa no está abierta' using errcode = 'P0005';
  end if;

  -- Ya está sentado en esta mesa: idempotente (devuelve ok sin cambios)
  if exists (select 1 from public.table_players
              where table_id = p_table_id and user_id = v_uid and status = 'seated') then
    return jsonb_build_object('table_id', p_table_id, 'status', 'seated');
  end if;

  -- Solo una mesa a la vez
  select table_id into v_other_table from public.table_players
   where user_id = v_uid and status = 'seated'
   limit 1;
  if v_other_table is not null then
    raise exception 'Ya estás sentado en otra mesa; sal antes de unirte a esta'
      using errcode = 'P0007';
  end if;

  -- Rate limiting por usuario en esta mesa
  v_cooldown := make_interval(secs => public.config_int('join_cooldown_seconds')::int);
  select last_action_at into v_last_action
    from public.table_players
   where table_id = p_table_id and user_id = v_uid;
  if v_last_action is not null and v_last_action + v_cooldown > now() then
    raise exception 'Acción demasiado rápida; espera unos segundos' using errcode = 'P0006';
  end if;

  -- Aforo: contar asientos con la mesa bloqueada
  select count(*) into v_seated from public.table_players
   where table_id = p_table_id and status = 'seated';
  if v_seated >= v_table.max_players then
    raise exception 'La mesa está llena' using errcode = 'P0008';
  end if;

  -- Saldo suficiente para la apuesta fija (sin mover fichas aún)
  select balance into v_balance from public.wallets where user_id = v_uid for update;
  if v_balance is null or v_balance < v_table.bet_amount then
    raise exception 'Saldo insuficiente: necesitas % fichas', v_table.bet_amount
      using errcode = 'P0009';
  end if;

  -- Sentarse (o volver si había salido antes)
  insert into public.table_players (table_id, user_id, status, last_action_at, joined_at, left_at)
  values (p_table_id, v_uid, 'seated', now(), now(), null)
  on conflict (table_id, user_id) do update
    set status = 'seated', last_action_at = now(), joined_at = now(), left_at = null;

  return jsonb_build_object('table_id', p_table_id, 'status', 'seated');
end;
$$;

create or replace function public.leave_table(p_table_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cooldown interval;
  v_last_action timestamptz;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  -- Rate limiting (mismo sobrante que join, evita spam join/leave)
  v_cooldown := make_interval(secs => public.config_int('join_cooldown_seconds')::int);
  select last_action_at into v_last_action
    from public.table_players
   where table_id = p_table_id and user_id = v_uid and status = 'seated';
  if not found then
    raise exception 'No estás sentado en esta mesa' using errcode = 'P0010';
  end if;
  if v_last_action is not null and v_last_action + v_cooldown > now() then
    raise exception 'Acción demasiado rápida; espera unos segundos' using errcode = 'P0006';
  end if;

  -- No se puede abandonar una mesa con una ronda en curso (la cancelación
  -- con reembolso la trata el motor de juego en la Fase 5).
  if exists (select 1 from public.rounds
              where table_id = p_table_id
                and status in ('waiting', 'in_progress')) then
    raise exception 'Hay una ronda en curso en esta mesa; no puedes salir ahora'
      using errcode = 'P0011';
  end if;

  update public.table_players
     set status = 'left', left_at = now(), last_action_at = now()
   where table_id = p_table_id and user_id = v_uid;

  return jsonb_build_object('table_id', p_table_id, 'status', 'left');
end;
$$;

revoke all on function public.join_table(uuid) from public, anon;
revoke all on function public.leave_table(uuid) from public, anon;
grant execute on function public.join_table(uuid) to authenticated;
grant execute on function public.leave_table(uuid) to authenticated;
