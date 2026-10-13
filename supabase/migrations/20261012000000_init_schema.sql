-- =============================================================
-- Fase 1 · Esquema inicial de Dado Royale
-- Tablas, enums, RLS, triggers de perfil/wallet, config y seeds.
--
-- Principios:
--  * RLS activado en TODAS las tablas; sin escritura directa en
--    wallets/ledger/rounds/round_players (solo RPC SECURITY DEFINER).
--  * Saldos en enteros (bigint), nunca decimales, nunca negativos.
--  * Ledger inmutable (sin UPDATE/DELETE).
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- Tipos enumerados
-- -------------------------------------------------------------
create type public.ledger_type as enum (
  'faucet',      -- fichas reclamadas gratis
  'bet_lock',    -- apuesta bloqueada al unirse a una ronda
  'payout',      -- premio pagado al ganador
  'refund',      -- devolución de apuesta (empate persistente / cancelación)
  'house_fee',   -- comisión de la casa
  'adjustment'   -- ajuste manual de admin (auditable)
);

create type public.table_status as enum ('open', 'in_round', 'closed');
create type public.table_player_status as enum ('seated', 'left');
create type public.round_status as enum ('waiting', 'in_progress', 'finished', 'cancelled');

-- -------------------------------------------------------------
-- Config global (sin números mágicos en el código)
-- -------------------------------------------------------------
create table public.config (
  key text primary key,
  value jsonb not null,
  description text
);

create or replace function public.config_int(p_key text)
returns bigint
language sql
stable
set search_path = public
as $$
  select (value #>> '{}')::bigint from public.config where key = p_key;
$$;

-- -------------------------------------------------------------
-- Perfiles: se crean por trigger al registrarse un usuario
-- -------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique
    check (username ~ '^[a-zA-Z0-9_]{3,20}$'),
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- Wallets: saldo entero, nunca negativo
-- -------------------------------------------------------------
create table public.wallets (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- Ledger: libro contable INMUTABLE y auditable.
-- amount: positivo = fichas que entran al usuario, negativo = salen.
-- user_id NULL solo para la fila de la casa (compensación house_fee).
-- -------------------------------------------------------------
create table public.ledger (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles (id) on delete restrict,
  type public.ledger_type not null,
  amount bigint not null,
  balance_after bigint,            -- NULL en filas de la casa
  round_id uuid,
  idempotency_key text unique,     -- evita movimientos duplicados
  created_at timestamptz not null default now()
);

create index ledger_user_created_idx on public.ledger (user_id, created_at desc);
create index ledger_round_idx on public.ledger (round_id) where round_id is not null;

-- -------------------------------------------------------------
-- Cuenta de la casa: una única fila
-- -------------------------------------------------------------
create table public.house_account (
  id boolean primary key default true check (id), -- garantiza UNA fila
  balance bigint not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

insert into public.house_account (id, balance) values (true, 0);

-- -------------------------------------------------------------
-- Mesas y jugadores sentados
-- -------------------------------------------------------------
create table public.tables (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  bet_amount bigint not null check (bet_amount > 0),
  max_players int not null check (max_players >= 2 and max_players <= 10),
  status public.table_status not null default 'open',
  created_at timestamptz not null default now()
);

create table public.table_players (
  table_id uuid not null references public.tables (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status public.table_player_status not null default 'seated',
  last_action_at timestamptz not null default now(), -- rate limiting
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (table_id, user_id)
);

-- -------------------------------------------------------------
-- Rondas y jugadores de cada ronda
-- -------------------------------------------------------------
create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  table_id uuid not null references public.tables (id) on delete cascade,
  status public.round_status not null default 'waiting',
  pot bigint not null default 0 check (pot >= 0),
  house_fee bigint not null default 0 check (house_fee >= 0),
  winner_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

-- FK diferida de ledger.round_id ahora que rounds existe
alter table public.ledger
  add constraint ledger_round_id_fkey
  foreign key (round_id) references public.rounds (id) on delete restrict;

create table public.round_players (
  round_id uuid not null references public.rounds (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  bet_amount bigint not null check (bet_amount > 0),
  dice1 smallint check (dice1 between 1 and 6),
  dice2 smallint check (dice2 between 1 and 6),
  total smallint generated always as (coalesce(dice1, 0) + coalesce(dice2, 0)) stored,
  tiebreak_attempts smallint not null default 0,
  is_winner boolean not null default false,
  primary key (round_id, user_id)
);

-- -------------------------------------------------------------
-- Trigger: crear perfil + wallet al registrarse un usuario.
-- SECURITY DEFINER para poder escribir en profiles desde auth.
-- -------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'username', ''),
      'jugador_' || substr(new.id::text, 1, 8)
    )
  );
  insert into public.wallets (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -------------------------------------------------------------
-- Trigger: no permitir UPDATE/DELETE en el ledger (inmutable)
-- -------------------------------------------------------------
create or replace function public.reject_ledger_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'El ledger es inmutable: no se permiten UPDATE ni DELETE';
end;
$$;

create trigger ledger_no_update before update on public.ledger
  for each row execute function public.reject_ledger_mutation();
create trigger ledger_no_delete before delete on public.ledger
  for each row execute function public.reject_ledger_mutation();

-- =============================================================
-- ROW LEVEL SECURITY
-- =============================================================
alter table public.config enable row level security;
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.ledger enable row level security;
alter table public.house_account enable row level security;
alter table public.tables enable row level security;
alter table public.table_players enable row level security;
alter table public.rounds enable row level security;
alter table public.round_players enable row level security;

-- config: lectura pública (valores del juego, nada sensible)
create policy "config: lectura para todos"
  on public.config for select using (true);

-- profiles: lectura pública (nombres para el lobby/ranking);
-- el usuario solo puede editar su avatar. La restricción de columnas
-- (username e is_admin intocables) se hace con privilegios de columna,
-- evitando subconsultas recursivas en la policy.
create policy "profiles: lectura para todos"
  on public.profiles for select using (true);
create policy "profiles: editar perfil propio"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- wallets: solo lectura del saldo propio. Sin escritura directa.
create policy "wallets: lectura del saldo propio"
  on public.wallets for select using (auth.uid() = user_id);

-- ledger: el usuario lee solo sus movimientos. Sin INSERT/UPDATE/DELETE
-- para authenticated/anon (las RPC SECURITY DEFINER escriben).
create policy "ledger: lectura de movimientos propios"
  on public.ledger for select using (auth.uid() = user_id);

-- house_account: solo lectura para admins (defensa en profundidad,
-- no solo ocultar en la UI).
create policy "house_account: solo admins"
  on public.house_account for select
  using ((select is_admin from public.profiles where id = auth.uid()));

-- tables: lectura pública (el lobby las lista).
create policy "tables: lectura para todos"
  on public.tables for select using (true);

-- table_players: lectura pública (ver quién está sentado);
-- la escritura es solo vía RPC join_table/leave_table.
create policy "table_players: lectura para todos"
  on public.table_players for select using (true);

-- rounds y round_players: lectura pública (historial y realtime).
create policy "rounds: lectura para todos"
  on public.rounds for select using (true);
create policy "round_players: lectura para todos"
  on public.round_players for select using (true);

-- Lectura completa para admins en tablas de auditoría
create policy "ledger: admins leen todo"
  on public.ledger for select
  using ((select is_admin from public.profiles where id = auth.uid()));

-- =============================================================
-- Permisos: sin escritura directa en tablas sensibles.
-- (RLS ya lo impide, pero revocamos también los GRANT por
-- defensa en profundidad; las RPC SECURITY DEFINER los ignoran.)
-- =============================================================
revoke insert, update, delete on public.wallets from anon, authenticated;
revoke insert, update, delete on public.ledger from anon, authenticated;
revoke insert, update, delete on public.house_account from anon, authenticated;
revoke insert, update, delete on public.rounds from anon, authenticated;
revoke insert, update, delete on public.round_players from anon, authenticated;
revoke insert, update, delete on public.table_players from anon, authenticated;
revoke insert, update, delete on public.tables from anon, authenticated;
revoke insert, update, delete on public.config from anon, authenticated;
revoke update on public.profiles from anon; -- sin login no hay nada
-- Los usuarios solo pueden tocar su avatar vía API (username/is_admin solo RPC/admin)
grant update (avatar_url) on public.profiles to authenticated;

-- =============================================================
-- Seeds: configuración inicial y mesas.
-- Ajustables sin tocar código, directo en la tabla config.
-- =============================================================
insert into public.config (key, value, description) values
  ('house_fee_percent',     '4',     'Comisión de la casa sobre el pozo (%)'),
  ('faucet_amount',         '1000',  'Fichas por reclamo del faucet'),
  ('faucet_cooldown_hours', '24',    'Horas mínimas entre reclamos'),
  ('min_players',           '2',     'Mínimo de jugadores para arrancar una ronda'),
  ('max_tiebreaks',         '3',     'Desempates máx. antes de reembolsar'),
  ('join_cooldown_seconds', '5',     'Rate limit básico para unirse/salir de mesas');

insert into public.tables (name, bet_amount, max_players) values
  ('Mesa Bronce',   10,  6),
  ('Mesa Plata',    50,  6),
  ('Mesa Oro',      100, 5),
  ('Mesa Diamante', 500, 4);

-- =============================================================
-- Realtime: publicar cambios que el frontend debe ver en vivo.
-- NOTA: con RLS activo, cada suscriptor solo recibe filas que
-- sus políticas le permiten leer.
-- =============================================================
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.tables;
    alter publication supabase_realtime add table public.table_players;
    alter publication supabase_realtime add table public.rounds;
    alter publication supabase_realtime add table public.round_players;
    alter publication supabase_realtime add table public.wallets;
    alter publication supabase_realtime add table public.ledger;
  end if;
end $$;
