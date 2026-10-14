import { useEffect, useState } from 'react';

import { useQuery } from '@tanstack/react-query';
import { Link, useParams } from 'react-router-dom';

import { supabase } from '@/lib/supabaseClient';

const EVENT_LABELS: Record<string, string> = {
  round_started: '🎬 Ronda iniciada',
  rolled: '🎲 Tirada de dados',
  dealt: '🃏 Cartas repartidas',
  war_draw: '🗡️ Carta robada',
  rps_choice: '✊ Elección registrada',
  insurance: '🛡️ Seguro',
  split: '⚔️ Mano separada',
  bj_hit: '♠️ Pedir carta',
  bj_stand: '✋ Plantarse',
  bj_double: '×2 Doblar',
  finished: '🏁 Ronda finalizada',
  settled: '🏁 Mano liquidada',
};

/** Replay: línea de tiempo de una ronda (de round_events). */
export function ReplayPage() {
  const { id: roundId } = useParams<{ id: string }>();
  const [step, setStep] = useState(0);
  const [playing, setPlaying] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['replay', roundId],
    enabled: !!roundId,
    queryFn: async () => {
      const { data: events, error } = await supabase
        .from('round_events')
        .select('*')
        .eq('round_id', roundId ?? '')
        .order('seq');
      if (error) throw error;
      const { data: round } = await supabase
        .from('rounds')
        .select('*, tables(name, game)')
        .eq('id', roundId ?? '')
        .single();
      return { events, round };
    },
  });

  const events = data?.events ?? [];
  const total = events.length;

  useEffect(() => {
    if (!playing || step >= total) {
      return;
    }
    const id = setTimeout(() => {
      setStep((s) => s + 1);
    }, 900);
    return () => {
      clearTimeout(id);
    };
  }, [playing, step, total]);

  if (isLoading) {
    return <p className="animate-pulse text-casino-muted">Cargando replay…</p>;
  }
  if (isError || !data?.round) {
    return (
      <p role="alert" className="text-casino-red">
        No se pudo cargar la ronda.
      </p>
    );
  }

  return (
    <main className="flex max-w-2xl flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">🔁 Replay de la ronda</h1>
        <p className="mt-1 text-sm text-casino-muted">
          {data.round.tables.name} · {new Date(data.round.created_at).toLocaleString('es')} ·{' '}
          {data.round.status}
        </p>
      </div>

      <div className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <div className="flex items-center justify-between gap-4">
          <button
            onClick={() => {
              if (step >= total) setStep(0);
              setPlaying(true);
            }}
            className="rounded-md bg-casino-gold px-5 py-2 font-semibold text-black"
          >
            {playing ? '⏸ Reproduciendo…' : step >= total ? '↺ Repetir' : '▶ Reproducir'}
          </button>
          <span className="text-sm text-casino-muted">
            Evento {Math.min(step, total)} de {total}
          </span>
        </div>

        <ol className="mt-5 flex flex-col gap-2">
          {events.slice(0, Math.max(step, 1)).map((e) => (
            <li
              key={e.id}
              className="rounded-lg border border-casino-border bg-casino-bg p-3 text-sm"
              style={{ animation: 'fade-in 0.3s ease' }}
            >
              <p className="font-medium">{EVENT_LABELS[e.event_type] ?? e.event_type}</p>
              <p className="mt-0.5 break-all font-mono text-xs text-casino-muted">
                {JSON.stringify(e.payload)}
              </p>
            </li>
          ))}
        </ol>
      </div>

      <Link to="/lobby" className="text-sm text-casino-gold underline">
        ← Volver al lobby
      </Link>
    </main>
  );
}
