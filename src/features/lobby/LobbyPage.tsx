import { useMemo, useState } from 'react';

import { TableCard } from './TableCard';
import { useTables } from './useTables';

/**
 * Lobby: lista de mesas en tiempo real con filtro por apuesta.
 * Los cambios (jugadores que entran/salen, estados) llegan por Realtime.
 */
export function LobbyPage() {
  const { data: tables, isLoading, isError, refetch } = useTables();
  const [filter, setFilter] = useState<number | null>(null);

  const betOptions = useMemo(
    () => [...new Set((tables ?? []).map((t) => t.bet_amount))].sort((a, b) => a - b),
    [tables],
  );
  const filtered = useMemo(
    () => (tables ?? []).filter((t) => filter === null || t.bet_amount === filter),
    [tables, filter],
  );

  return (
    <main className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Lobby</h1>
          <p className="mt-1 text-sm text-casino-muted">
            Siéntate en una mesa. La apuesta se bloquea cuando comienza la ronda. Comisión de la
            casa: 4% del pozo.
          </p>
        </div>
        <div
          className="flex flex-wrap items-center gap-2"
          role="group"
          aria-label="Filtrar por apuesta"
        >
          <button
            onClick={() => {
              setFilter(null);
            }}
            className={`rounded-md px-3 py-1.5 text-sm font-medium ${
              filter === null
                ? 'bg-casino-gold text-black'
                : 'border border-casino-border text-casino-muted'
            }`}
          >
            Todas
          </button>
          {betOptions.map((bet) => (
            <button
              key={bet}
              onClick={() => {
                setFilter(bet);
              }}
              className={`rounded-md px-3 py-1.5 text-sm font-medium ${
                filter === bet
                  ? 'bg-casino-gold text-black'
                  : 'border border-casino-border text-casino-muted'
              }`}
            >
              {bet} 🪙
            </button>
          ))}
        </div>
      </div>

      {isLoading && <p className="animate-pulse text-casino-muted">Cargando mesas…</p>}
      {isError && (
        <div role="alert" className="rounded-xl border border-casino-red/50 bg-casino-red/10 p-4">
          <p className="text-casino-red">No se pudieron cargar las mesas.</p>
          <button
            onClick={() => void refetch()}
            className="mt-2 rounded-md border border-casino-border px-3 py-1.5 text-sm text-casino-muted hover:text-casino-text"
          >
            Reintentar
          </button>
        </div>
      )}
      {tables && filtered.length === 0 && (
        <p className="text-casino-muted">No hay mesas con ese filtro.</p>
      )}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {filtered.map((table) => (
          <TableCard key={table.id} table={table} />
        ))}
      </div>
    </main>
  );
}
