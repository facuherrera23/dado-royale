-- =============================================================
-- Fase 3 · RPC claim_faucet: fichas gratis con cooldown.
--
-- Seguridad:
--  * SECURITY DEFINER + search_path fijo: escribe wallet/ledger
--    saltándose RLS, pero valida auth.uid() y el cooldown aquí.
--  * Atómica: una sola transacción, bloqueo FOR UPDATE.
--  * Idempotente: la misma ventana de cooldown jamás concede dos veces.
-- =============================================================

create or replace function public.claim_faucet()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_amount bigint;
  v_cooldown interval;
  v_last_claim timestamptz;
  v_next_claim timestamptz;
  v_balance bigint;
  v_idem text;
begin
  -- 1. Validación de autenticación (servidor, no se fía del cliente)
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  v_amount   := public.config_int('faucet_amount');
  v_cooldown := make_interval(hours => public.config_int('faucet_cooldown_hours')::int);

  -- 2. Cooldown: última concesión faucet de ESTE usuario
  select max(created_at) into v_last_claim
    from public.ledger
   where user_id = v_uid and type = 'faucet';

  if v_last_claim is not null and v_last_claim + v_cooldown > now() then
    v_next_claim := v_last_claim + v_cooldown;
    raise exception 'Cooldown activo; podrás reclamar a las %', v_next_claim
      using errcode = 'P0002',
            detail = v_next_claim::text;
  end if;

  -- 3. Bloquear la fila de la wallet y acreditar (todo en esta transacción)
  update public.wallets
     set balance = balance + v_amount,
         updated_at = now()
   where user_id = v_uid
  returning balance into v_balance;

  if not found then
    raise exception 'No existe wallet para el usuario' using errcode = 'P0003';
  end if;

  -- 4. Registrar en el ledger con clave idempotente por ventana de cooldown:
  --    reintentos de la MISMA ventana no duplican el movimiento.
  v_idem := format('faucet:%s:%s', v_uid,
                   floor(extract(epoch from now()) / extract(epoch from v_cooldown)));

  insert into public.ledger (user_id, type, amount, balance_after, idempotency_key)
  values (v_uid, 'faucet', v_amount, v_balance, v_idem)
  on conflict (idempotency_key) do nothing;

  return jsonb_build_object(
    'balance', v_balance,
    'claimed', v_amount,
    'next_claim_at', now() + v_cooldown
  );
end;
$$;

-- Solo usuarios autenticados pueden ejecutar esta RPC
revoke all on function public.claim_faucet() from public, anon;
grant execute on function public.claim_faucet() to authenticated;
