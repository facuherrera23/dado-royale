-- =============================================================
-- Fase 7 · Admin y ranking
--
--  * get_admin_stats(): solo admins (comprobado en servidor vía
--    profiles.is_admin). La UI oculta el enlace, pero la seguridad
--    real la da esta función + las policies RLS (defensa en profundidad).
--  * is_admin() helper SECURITY DEFINER para reusar en policies sin
--    subconsultas repetidas.
-- =============================================================

create or replace function public.is_admin(p_uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = p_uid), false);
$$;

-- Estadísticas de la casa solo para administradores
create or replace function public.get_admin_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Acceso denegado: se requiere rol admin' using errcode = 'P0403';
  end if;

  select jsonb_build_object(
    'house_balance', (select balance from public.house_account where id = true),
    'total_fees', coalesce((select sum(amount) from public.ledger where type = 'house_fee'), 0),
    'total_rounds', (select count(*) from public.rounds),
    'finished_rounds', (select count(*) from public.rounds where status = 'finished'),
    'cancelled_rounds', (select count(*) from public.rounds where status = 'cancelled'),
    'total_faucet_given', coalesce((select sum(amount) from public.ledger where type = 'faucet'), 0),
    'total_payouts', coalesce((select sum(amount) from public.ledger where type = 'payout'), 0),
    'registered_users', (select count(*) from public.profiles)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.is_admin(uuid) from public, anon;
revoke all on function public.get_admin_stats() from public, anon;
grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.get_admin_stats() to authenticated;
