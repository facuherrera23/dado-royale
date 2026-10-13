import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabaseClient';

/** Ranking global: fichas ganadas y rondas ganadas (RPC get_leaderboard). */
export function RankingPage() {
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['leaderboard'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_leaderboard', { p_limit: 20 });
      if (error) throw error;
      return data.filter((r) => r.total_won > 0 || r.rounds_won > 0);
    },
  });

  return (
    <main className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold">🏆 Ranking</h1>

      {isLoading && <p className="animate-pulse text-casino-muted">Cargando ranking…</p>}
      {isError && (
        <div role="alert" className="rounded-xl border border-casino-red/50 bg-casino-red/10 p-4">
          <p className="text-casino-red">No se pudo cargar el ranking.</p>
          <button
            onClick={() => void refetch()}
            className="mt-2 rounded-md border border-casino-border px-3 py-1.5 text-sm text-casino-muted hover:text-casino-text"
          >
            Reintentar
          </button>
        </div>
      )}
      {data && data.length === 0 && (
        <p className="text-casino-muted">Nadie ha ganado fichas todavía. ¡Juega una ronda!</p>
      )}

      {data && data.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-casino-border bg-casino-surface">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-casino-border text-left text-casino-muted">
                <th className="px-4 py-3 font-medium">#</th>
                <th className="px-4 py-3 font-medium">Jugador</th>
                <th className="px-4 py-3 text-right font-medium">Rondas ganadas</th>
                <th className="px-4 py-3 text-right font-medium">Fichas ganadas</th>
              </tr>
            </thead>
            <tbody>
              {data.map((row, i) => (
                <tr key={row.username} className="border-b border-casino-border/50">
                  <td className="px-4 py-3">
                    {i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : i + 1}
                  </td>
                  <td className="px-4 py-3 font-medium">{row.username}</td>
                  <td className="px-4 py-3 text-right">{row.rounds_won}</td>
                  <td className="px-4 py-3 text-right font-semibold text-casino-gold">
                    {row.total_won.toLocaleString('es')} 🪙
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  );
}
