import { useState } from 'react';

import { LEDGER_PAGE_SIZE, useLedgerHistory } from './useLedger';

const TYPE_LABELS: Record<string, string> = {
  faucet: 'Fichas gratis',
  bet_lock: 'Apuesta',
  payout: 'Premio',
  refund: 'Devolución',
  house_fee: 'Comisión casa',
  adjustment: 'Ajuste',
};

/** Historial paginado de movimientos del usuario. */
export function LedgerHistory() {
  const [page, setPage] = useState(0);
  const { data, isLoading, isError } = useLedgerHistory(page);

  const totalPages = data ? Math.max(1, Math.ceil(data.total / LEDGER_PAGE_SIZE)) : 1;

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">Historial de movimientos</h2>

      {isLoading && <p className="mt-4 animate-pulse text-casino-muted">Cargando…</p>}
      {isError && (
        <p role="alert" className="mt-4 text-casino-red">
          No se pudo cargar el historial.
        </p>
      )}
      {data && data.rows.length === 0 && (
        <p className="mt-4 text-casino-muted">Aún no tienes movimientos. ¡Reclama tus fichas!</p>
      )}
      {data && data.rows.length > 0 && (
        <>
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-casino-border text-left text-casino-muted">
                  <th className="py-2 pr-4 font-medium">Fecha</th>
                  <th className="py-2 pr-4 font-medium">Tipo</th>
                  <th className="py-2 pr-4 text-right font-medium">Importe</th>
                  <th className="py-2 text-right font-medium">Saldo tras movimiento</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.map((row) => (
                  <tr key={row.id} className="border-b border-casino-border/50">
                    <td className="py-2 pr-4 text-casino-muted">
                      {new Date(row.created_at).toLocaleString('es')}
                    </td>
                    <td className="py-2 pr-4">{TYPE_LABELS[row.type] ?? row.type}</td>
                    <td
                      className={`py-2 pr-4 text-right font-semibold ${
                        row.amount >= 0 ? 'text-casino-green' : 'text-casino-red'
                      }`}
                    >
                      {row.amount >= 0 ? '+' : ''}
                      {row.amount.toLocaleString('es')}
                    </td>
                    <td className="py-2 text-right text-casino-muted">
                      {row.balance_after?.toLocaleString('es') ?? '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <nav
            className="mt-4 flex items-center justify-between"
            aria-label="paginación del historial"
          >
            <button
              onClick={() => {
                setPage((p) => Math.max(0, p - 1));
              }}
              disabled={page === 0}
              className="rounded-md border border-casino-border px-3 py-1.5 text-sm text-casino-muted enabled:hover:text-casino-text disabled:opacity-40"
            >
              ← Anterior
            </button>
            <span className="text-sm text-casino-muted">
              Página {page + 1} de {totalPages}
            </span>
            <button
              onClick={() => {
                setPage((p) => p + 1);
              }}
              disabled={page + 1 >= totalPages}
              className="rounded-md border border-casino-border px-3 py-1.5 text-sm text-casino-muted enabled:hover:text-casino-text disabled:opacity-40"
            >
              Siguiente →
            </button>
          </nav>
        </>
      )}
    </section>
  );
}
