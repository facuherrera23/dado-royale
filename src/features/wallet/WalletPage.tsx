import { BalanceCard } from './Balance';
import { FaucetButton } from './FaucetButton';
import { LedgerHistory } from './LedgerHistory';

/** Página de billetera: saldo, faucet con cooldown e historial paginado. */
export function WalletPage() {
  return (
    <main className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold">Billetera</h1>
      <BalanceCard />
      <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <h2 className="text-lg font-semibold">Fichas gratis</h2>
        <div className="mt-4">
          <FaucetButton />
        </div>
      </section>
      <LedgerHistory />
    </main>
  );
}
