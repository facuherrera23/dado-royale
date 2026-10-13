import { useEffect, useState } from 'react';

import { useConfig } from '@/lib/useConfig';

import { useClaimFaucet, useLastFaucet } from './useLedger';

function formatRemaining(ms: number): string {
  const totalSeconds = Math.ceil(ms / 1000);
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  return h > 0 ? `${String(h)}h ${String(m)}m` : `${String(m)}m ${String(s)}s`;
}

/** Botón de reclamo con cooldown visible y cuenta atrás en vivo. */
export function FaucetButton() {
  const { data: config } = useConfig();
  const { data: lastFaucet } = useLastFaucet();
  const claim = useClaimFaucet();
  const cooldownHours = config?.get('faucet_cooldown_hours') ?? 24;
  const amount = config?.get('faucet_amount') ?? 0;

  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => {
      setNow(Date.now());
    }, 1000);
    return () => {
      clearInterval(id);
    };
  }, []);

  const nextClaimAt = lastFaucet ? new Date(lastFaucet).getTime() + cooldownHours * 3600 * 1000 : 0;
  const remaining = nextClaimAt - now;
  const onCooldown = remaining > 0;

  const cooldownError = claim.error?.message.includes('Cooldown activo')
    ? 'El servidor rechazó el reclamo: cooldown activo.'
    : claim.error?.message;

  return (
    <div className="flex flex-col gap-2">
      <button
        onClick={() => {
          claim.mutate();
        }}
        disabled={onCooldown || claim.isPending}
        className="rounded-md bg-casino-green px-4 py-2 font-semibold text-white transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
      >
        {claim.isPending
          ? 'Reclamando…'
          : onCooldown
            ? `Disponible en ${formatRemaining(remaining)}`
            : `Reclamar ${String(amount)} fichas gratis`}
      </button>
      {claim.isSuccess && (
        <p role="status" className="text-sm text-casino-green">
          +{String(claim.data.claimed)} fichas añadidas a tu saldo.
        </p>
      )}
      {claim.isError && (
        <p role="alert" className="text-sm text-casino-red">
          {cooldownError ?? 'No se pudo reclamar. Inténtalo de nuevo.'}
        </p>
      )}
    </div>
  );
}
