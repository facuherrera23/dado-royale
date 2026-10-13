import { useConfig } from '@/lib/useConfig';

import { useWallet } from './useWallet';

/** Muestra el saldo actual junto al nickname en la barra superior. */
export function BalanceBadge() {
  const { data: wallet } = useWallet();
  return (
    <span
      className="rounded-md border border-casino-gold/40 bg-casino-bg px-3 py-1.5 text-sm font-semibold text-casino-gold"
      aria-label="saldo actual"
    >
      🪙 {wallet ? wallet.balance.toLocaleString('es') : '…'}
    </span>
  );
}

/** Tarjeta de saldo grande para la página de billetera. */
export function BalanceCard() {
  const { data: wallet, isLoading, isError } = useWallet();
  const { data: config } = useConfig();

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
      <h2 className="text-sm font-medium text-casino-muted">Saldo actual</h2>
      {isLoading && <p className="mt-2 animate-pulse text-casino-muted">Cargando…</p>}
      {isError && (
        <p role="alert" className="mt-2 text-casino-red">
          No se pudo cargar el saldo.
        </p>
      )}
      {wallet && (
        <p className="mt-2 text-4xl font-bold text-casino-gold">
          {wallet.balance.toLocaleString('es')}
          <span className="ml-2 text-base font-normal text-casino-muted">fichas</span>
        </p>
      )}
      <p className="mt-4 text-xs text-casino-muted">
        Las fichas son virtuales y sin valor monetario. {config?.get('faucet_amount') ?? '…'} fichas
        gratis cada {config?.get('faucet_cooldown_hours') ?? '…'}h.
      </p>
    </section>
  );
}
