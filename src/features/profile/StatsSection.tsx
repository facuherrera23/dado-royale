/** Sección de estadísticas personales por juego (RPC get_my_stats). */
import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabaseClient';

const GAME_LABELS: Record<string, string> = {
  dice: '🎲 Dados',
  poker: '🃏 Póker 2 cartas',
  blackjack: '♠ Blackjack',
};

interface GameStats {
  game: string;
  played: number;
  won: number;
  lost: number;
  pushed: number;
  wagered: number;
  net: number;
}

export function StatsSection() {
  const { data, isLoading } = useQuery({
    queryKey: ['my-stats'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_my_stats');
      if (error) throw error;
      return data as unknown as GameStats[];
    },
  });

  const stats = (data ?? []).filter((g) => g.played > 0);

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">Mis estadísticas</h2>
      {isLoading && <p className="mt-4 animate-pulse text-casino-muted">Cargando…</p>}
      {data && stats.length === 0 && (
        <p className="mt-4 text-sm text-casino-muted">
          Aún no has terminado ninguna ronda. ¡Juega tu primera partida!
        </p>
      )}
      {stats.length > 0 && (
        <div className="mt-4 grid gap-4 sm:grid-cols-3">
          {stats.map((g) => {
            const winrate = g.played > 0 ? Math.round((g.won / g.played) * 100) : 0;
            return (
              <div key={g.game} className="rounded-lg border border-casino-border bg-casino-bg p-4">
                <p className="font-semibold">{GAME_LABELS[g.game] ?? g.game}</p>
                <dl className="mt-2 space-y-1 text-sm text-casino-muted">
                  <div className="flex justify-between">
                    <dt>Manos</dt>
                    <dd className="text-casino-text">{g.played}</dd>
                  </div>
                  <div className="flex justify-between">
                    <dt>Victorias</dt>
                    <dd className="text-casino-text">
                      {g.won} ({String(winrate)}%)
                    </dd>
                  </div>
                  <div className="flex justify-between">
                    <dt>Apostado</dt>
                    <dd className="text-casino-text">{g.wagered.toLocaleString('es')} 🪙</dd>
                  </div>
                  <div className="flex justify-between">
                    <dt>Neto</dt>
                    <dd
                      className={
                        g.net >= 0
                          ? 'font-semibold text-casino-green'
                          : 'font-semibold text-casino-red'
                      }
                    >
                      {g.net >= 0 ? '+' : ''}
                      {g.net.toLocaleString('es')} 🪙
                    </dd>
                  </div>
                </dl>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
