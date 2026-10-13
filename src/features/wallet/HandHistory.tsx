import { useState } from 'react';

import { HANDS_PAGE_SIZE, useHandHistory, type HandHistoryRow } from './useHandHistory';

const GAME_LABELS: Record<string, string> = {
  dice: '🎲 Dados',
  poker: '🃏 Póker',
  blackjack: '♠ Blackjack',
};

function outcomeLabel(won: boolean, result: string | null): { text: string; cls: string } {
  if (won) return { text: 'Ganada', cls: 'text-casino-green' };
  if (result === 'blackjack') return { text: 'Blackjack 🎉', cls: 'text-casino-green' };
  if (result === 'win') return { text: 'Ganada', cls: 'text-casino-green' };
  if (result === 'push') return { text: 'Push', cls: 'text-casino-muted' };
  if (result === 'loss') return { text: 'Perdida', cls: 'text-casino-red' };
  return { text: 'Jugada', cls: 'text-casino-muted' };
}

function gameLabel(row: HandHistoryRow): string {
  const game = row.rounds.tables === null ? null : row.rounds.tables.game;
  return game === null ? '—' : (GAME_LABELS[game] ?? game);
}

/** Historial de manos del usuario con juego, apuesta y resultado. */
export function HandHistory() {
  const [page, setPage] = useState(0);
  const { data, isLoading, isError } = useHandHistory(page);
  const totalPages = data ? Math.max(1, Math.ceil(data.total / HANDS_PAGE_SIZE)) : 1;

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">Mis manos jugadas</h2>
      {isLoading && <p className="mt-4 animate-pulse text-casino-muted">Cargando…</p>}
      {isError && (
        <p role="alert" className="mt-4 text-casino-red">
          No se pudo cargar el historial de manos.
        </p>
      )}
      {data && data.rows.length === 0 && (
        <p className="mt-4 text-casino-muted">Aún no has jugado ninguna mano.</p>
      )}
      {data && data.rows.length > 0 && (
        <>
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-casino-border text-left text-casino-muted">
                  <th className="py-2 pr-4 font-medium">Juego</th>
                  <th className="py-2 pr-4 font-medium">Apuesta</th>
                  <th className="py-2 pr-4 font-medium">Mi mano</th>
                  <th className="py-2 text-right font-medium">Resultado</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.map((row) => {
                  const o = outcomeLabel(row.is_winner, row.result);
                  const hand =
                    row.rounds.tables?.game === 'blackjack'
                      ? row.cards.join(', ')
                      : row.rounds.tables?.game === 'poker'
                        ? [row.card1, row.card2].filter((c) => c !== null).join(', ')
                        : row.dice1 !== null
                          ? `${String(row.dice1)}+${String(row.dice2 ?? 0)}`
                          : '—';
                  return (
                    <tr
                      key={`${row.round_id}-${String(row.hand_no)}`}
                      className="border-b border-casino-border/50"
                    >
                      <td className="py-2 pr-4">{gameLabel(row)}</td>
                      <td className="py-2 pr-4">{row.bet_amount.toLocaleString('es')} 🪙</td>
                      <td className="py-2 pr-4 text-casino-muted">{hand}</td>
                      <td className={`py-2 text-right font-semibold ${o.cls}`}>{o.text}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <nav className="mt-4 flex items-center justify-between" aria-label="paginación de manos">
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
