-- =============================================================
-- Fase 16 · Verificación KYC ligera (18+) con gate de juego
--
--  * profiles: full_name, date_of_birth, country, doc_hash (SHA-256,
--    nunca el documento en claro), kyc_verified, kyc_at.
--  * submit_kyc(...): valida nombre, fecha (>=18 años), país y
--    guarda el hash del documento. Idempotente.
--  * join_table/set_bet exigen kyc_verified (no se juega sin
--    verificar). Los datos sensibles no son editables por el usuario.
-- =============================================================

alter table public.profiles
  add column if not exists full_name text,
  add column if not exists date_of_birth date,
  add column if not exists country text,
  add column if not exists doc_hash text,
  add column if not exists kyc_verified boolean not null default false,
  add column if not exists kyc_at timestamptz;

create or replace function public.submit_kyc(
  p_full_name text,
  p_dob date,
  p_country text,
  p_doc_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_age int;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  p_full_name := nullif(trim(p_full_name), '');
  p_country := upper(nullif(trim(p_country), ''));
  p_doc_id := nullif(trim(p_doc_id), '');

  if p_full_name is null or position(' ' in p_full_name) = 0 or length(p_full_name) < 5 then
    raise exception 'Introduce tu nombre completo (nombre y apellido)' using errcode = 'P0030';
  end if;
  if p_dob is null then
    raise exception 'Fecha de nacimiento obligatoria' using errcode = 'P0031';
  end if;
  v_age := extract(year from age(p_dob));
  if v_age < 18 then
    raise exception 'Debes ser mayor de 18 años para jugar' using errcode = 'P0032';
  end if;
  if p_country is null or length(p_country) <> 2 then
    raise exception 'Introduce el código ISO de tu país (ej: ES, AR, MX)' using errcode = 'P0033';
  end if;
  if p_doc_id is null or length(p_doc_id) < 6 then
    raise exception 'Documento inválido' using errcode = 'P0034';
  end if;

  insert into public.profiles (id, username, full_name, date_of_birth, country,
                               doc_hash, kyc_verified, kyc_at)
  values (v_uid,
          'jugador_' || substr(v_uid::text, 1, 8),
          p_full_name, p_dob, p_country,
          encode(extensions.digest(upper(p_doc_id), 'sha256'), 'hex'),
          true, now())
  on conflict (id) do update
    set full_name = excluded.full_name,
        date_of_birth = excluded.date_of_birth,
        country = excluded.country,
        doc_hash = excluded.doc_hash,
        kyc_verified = true,
        kyc_at = now();

  return jsonb_build_object('kyc_verified', true);
end;
$$;

revoke all on function public.submit_kyc(text, date, text, text) from public, anon;
grant execute on function public.submit_kyc(text, date, text, text) to authenticated;

-- Gate: sin KYC no se puede sentar
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

  -- KYC: verificar antes de sentarse en cualquier mesa
  if not coalesce((select kyc_verified from public.profiles where id = v_uid), false) then
    raise exception 'Verifica tu identidad (KYC) antes de jugar' using errcode = 'P0035';
  end if;

  select * into v_table from public.tables where id = p_table_id for update;
  if not found then
    raise exception 'La mesa no existe' using errcode = 'P0004';
  end if;
  if v_table.status <> 'open' then
    raise exception 'La mesa no está abierta' using errcode = 'P0005';
  end if;

  if exists (select 1 from public.table_players
              where table_id = p_table_id and user_id = v_uid and status = 'seated') then
    return jsonb_build_object('table_id', p_table_id, 'status', 'seated');
  end if;

  select table_id into v_other_table from public.table_players
   where user_id = v_uid and status = 'seated'
   limit 1;
  if v_other_table is not null then
    raise exception 'Ya estás sentado en otra mesa; sal antes de unirte a esta'
      using errcode = 'P0007';
  end if;

  v_cooldown := make_interval(secs => public.config_int('join_cooldown_seconds')::int);
  select last_action_at into v_last_action
    from public.table_players
   where table_id = p_table_id and user_id = v_uid;
  if v_last_action is not null and v_last_action + v_cooldown > now() then
    raise exception 'Acción demasiado rápida; espera unos segundos' using errcode = 'P0006';
  end if;

  select count(*) into v_seated from public.table_players
   where table_id = p_table_id and status = 'seated';
  if v_seated >= v_table.max_players then
    raise exception 'La mesa está llena' using errcode = 'P0008';
  end if;

  select balance into v_balance from public.wallets where user_id = v_uid for update;
  if v_balance is null or v_balance < v_table.bet_amount then
    raise exception 'Saldo insuficiente: necesitas % fichas', v_table.bet_amount
      using errcode = 'P0009';
  end if;

  insert into public.table_players (table_id, user_id, status, last_action_at, joined_at, left_at)
  values (p_table_id, v_uid, 'seated', now(), now(), null)
  on conflict (table_id, user_id) do update
    set status = 'seated', last_action_at = now(), joined_at = now(), left_at = null;

  return jsonb_build_object('table_id', p_table_id, 'status', 'seated');
end;
$$;

-- set_bet: gate KYC
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
  if not coalesce((select kyc_verified from public.profiles where id = v_uid), false) then
    raise exception 'Verifica tu identidad (KYC) antes de apostar' using errcode = 'P0035';
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
