import { useEffect, useState } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';
import { toast } from '@/lib/toastStore';
import type { Tables } from '@/types/database.types';

type Tournament = Tables<'tournaments'> & { players_count?: number };

const GAME_ICONS: Record<string, string> = {
  dice: '🎲',
  poker: '🃏',
  blackjack: '♠️',
  war: '🗡️',
  rps: '✊',
};

function fmtCountdown(to: string): string {
  const ms = new Date(to).getTime() - Date.now();
  if (ms <= 0) return 'Cerrando…';
  const d = Math.floor(ms / 86400000);
  const h = Math.floor((ms % 86400000) / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  return d > 0 ? `${String(d)}d ${String(h)}h` : `${String(h)}h ${String(m)}m`;
}

/** Página de torneos: inscripción, standings en vivo y finalización manual. */
export function TournamentsPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [now, setNow] = useState(() => Date.now());

  // Reloj de la cuenta atrás
  useEffect(() => {
    const id = setInterval(() => {
      setNow(Date.now());
    }, 30000);
    return () => {
      clearInterval(id);
    };
  }, []);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['tournaments'],
    queryFn: async () => {
      const [{ data: ts, error: e1 }, { data: tps, error: e2 }] = await Promise.all([
        supabase.from('tournaments').select('*').order('starts_at', { ascending: false }).limit(20),
        supabase.from('tournament_players').select('tournament_id, user_id'),
      ]);
      if (e1) throw e1;
      if (e2) throw e2;
      return {
        tournaments: ts,
        myEntries: new Set(tps.filter((p) => p.user_id === user?.id).map((p) => p.tournament_id)),
        counts: tps.reduce<Map<string, number>>(
          (m, p) => m.set(p.tournament_id, (m.get(p.tournament_id) ?? 0) + 1),
          new Map(),
        ),
      };
    },
  });

  const [standingsFor, setStandingsFor] = useState<string | null>(null);
  const { data: standings } = useQuery({
    queryKey: ['tournament-standings', standingsFor],
    enabled: !!standingsFor,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_tournament_standings', {
        p_tournament_id: standingsFor ?? '',
      });
      if (error) throw error;
      return data;
    },
  });

  const register = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('register_tournament', { p_tournament_id: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast('success', '🏆 ¡Inscrito al torneo!');
      void queryClient.invalidateQueries({ queryKey: ['tournaments'] });
      void queryClient.invalidateQueries({ queryKey: ['wallet', user?.id] });
    },
    onError: (e) => {
      toast('error', e.message);
    },
  });

  const finalize = useMutation({
    mutationFn: async (id: string) => {
      const { data, error } = await supabase.rpc('finalize_tournament', { p_tournament_id: id });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      toast('info', 'Torneo finalizado');
      void queryClient.invalidateQueries({ queryKey: ['tournaments'] });
    },
    onError: (e) => {
      toast('error', e.message);
    },
  });

  return (
    <main className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">🏆 Torneos semanales</h1>
        <p className="mt-1 text-sm text-casino-muted">
          Buy-in bloqueado; gana quien más fichas netas consiga en su juego durante la ventana.
          Premios: 50% / 30% / 20% del pozo neto (casa 4%).
        </p>
      </div>

      {isLoading && <p className="animate-pulse text-casino-muted">Cargando torneos…</p>}
      {isError && (
        <p role="alert" className="text-casino-red">
          No se pudieron cargar los torneos.{' '}
          <button onClick={() => void refetch()} className="underline">
            Reintentar
          </button>
        </p>
      )}
      {data && data.tournaments.length === 0 && (
        <p className="text-casino-muted">No hay torneos activos todavía.</p>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        {data?.tournaments.map((t: Tournament) => {
          const count = data.counts.get(t.id) ?? 0;
          const mine = data.myEntries.has(t.id);
          const over = t.ends_at <= new Date(now - 300000).toISOString();
          return (
            <article
              key={t.id}
              className="rounded-xl border border-casino-border bg-casino-surface p-5"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-semibold">
                    {GAME_ICONS[t.game]} {t.name}
                  </p>
                  <p className="mt-1 text-sm text-casino-muted">
                    Buy-in{' '}
                    <strong className="text-casino-gold">{t.buy_in.toLocaleString('es')} 🪙</strong>
                    {' · '}
                    {count} inscritos ·{' '}
                    {t.status === 'finished'
                      ? 'Finalizado'
                      : t.status === 'cancelled'
                        ? 'Cancelado'
                        : `Cierra en ${fmtCountdown(t.ends_at)}`}
                  </p>
                </div>
                <span
                  className={`rounded-full px-2.5 py-1 text-xs font-semibold ${
                    t.status === 'finished'
                      ? 'bg-casino-green/20 text-casino-green'
                      : t.status === 'cancelled'
                        ? 'bg-casino-red/20 text-casino-red'
                        : 'bg-casino-gold/20 text-casino-gold'
                  }`}
                >
                  {t.status}
                </span>
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                {t.status !== 'finished' && t.status !== 'cancelled' && !mine && (
                  <button
                    onClick={() => {
                      register.mutate(t.id);
                    }}
                    disabled={register.isPending}
                    className="rounded-md bg-casino-green px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
                  >
                    Inscribirme ({t.buy_in} 🪙)
                  </button>
                )}
                {mine && (
                  <span className="rounded-md border border-casino-green/50 px-4 py-2 text-sm text-casino-green">
                    ✓ Inscrito
                  </span>
                )}
                <button
                  onClick={() => {
                    setStandingsFor((s) => (s === t.id ? null : t.id));
                  }}
                  className="rounded-md border border-casino-border px-4 py-2 text-sm text-casino-muted hover:text-casino-text"
                >
                  {standingsFor === t.id ? 'Ocultar' : 'Ver'} clasificación
                </button>
                {over && t.status !== 'finished' && t.status !== 'cancelled' && (
                  <button
                    onClick={() => {
                      finalize.mutate(t.id);
                    }}
                    disabled={finalize.isPending}
                    className="rounded-md bg-casino-gold px-4 py-2 text-sm font-semibold text-black disabled:opacity-40"
                  >
                    Finalizar ahora
                  </button>
                )}
              </div>

              {standingsFor === t.id && (
                <table className="mt-3 w-full text-sm">
                  <thead>
                    <tr className="border-b border-casino-border text-left text-casino-muted">
                      <th className="py-1 font-medium">#</th>
                      <th className="py-1 font-medium">Jugador</th>
                      <th className="py-1 text-right font-medium">Victorias</th>
                      <th className="py-1 text-right font-medium">Neto</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(standings ?? []).map((s, i) => (
                      <tr key={s.username} className="border-b border-casino-border/50">
                        <td className="py-1.5">
                          {i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : i + 1}
                        </td>
                        <td className="py-1.5">{s.username}</td>
                        <td className="py-1.5 text-right">{s.won}</td>
                        <td
                          className={`py-1.5 text-right font-semibold ${s.net >= 0 ? 'text-casino-green' : 'text-casino-red'}`}
                        >
                          {s.net >= 0 ? '+' : ''}
                          {s.net.toLocaleString('es')}
                        </td>
                      </tr>
                    ))}
                    {(standings ?? []).length === 0 && (
                      <tr>
                        <td colSpan={4} className="py-3 text-center text-casino-muted">
                          Aún sin puntos. ¡Juega rondas durante la ventana!
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              )}
            </article>
          );
        })}
      </div>
    </main>
  );
}
