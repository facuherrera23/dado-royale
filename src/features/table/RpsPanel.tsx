import { useState } from 'react';

import { useMutation, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

import type { Round, RoundPlayer } from './useRound';

const CHOICES = [
  { value: 1, label: '✊ Piedra' },
  { value: 2, label: '✋ Papel' },
  { value: 3, label: '✌️ Tijeras' },
] as const;

interface Props {
  tableId: string;
  data: { round: Round | null; players: RoundPlayer[] };
  seated: boolean;
}

/** Panel de Piedra-Papel-Tijera: elección oculta hasta que todos eligen. */
export function RpsPanel({ tableId, data, seated }: Props) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [chosen, setChosen] = useState<number | null>(null);

  const roundId = data.round === null ? '' : data.round.id;
  const play = useMutation({
    mutationFn: async (choice: number) => {
      const { data: res, error } = await supabase.rpc('rps_play', {
        p_round_id: roundId,
        p_choice: choice,
      });
      if (error) throw error;
      return res as { status: string };
    },
    onSuccess: (res) => {
      void queryClient.invalidateQueries({ queryKey: ['current-round', tableId] });
      if (res.status !== 'waiting_choices') {
        setChosen(null);
      }
    },
  });

  const round = data.round;
  if (!round) return null;

  const me = data.players.find((p) => p.user_id === user?.id);
  const iWon = round.status === 'finished' && round.winner_id === user?.id;
  const waiting = round.status === 'in_progress';

  return (
    <section className="rounded-xl border border-casino-gold/40 bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">✊ Piedra · Papel · Tijera</h2>
      <p className="mt-1 text-sm text-casino-muted">
        Elecciones secretas hasta que todos elijan · la banca cobra 4% del pozo
      </p>

      {round.status === 'finished' && (
        <div
          role="status"
          className={`mt-4 rounded-lg border p-4 ${
            iWon ? 'border-casino-green/50 bg-casino-green/10' : 'border-casino-border bg-casino-bg'
          }`}
        >
          <p className="font-semibold">
            {iWon
              ? `🏆 ¡Ganaste ${String(round.pot - round.house_fee)} 🪙!`
              : `🏆 Ganador: ${data.players.find((p) => p.user_id === round.winner_id)?.profiles?.username ?? '—'}`}
          </p>
        </div>
      )}
      {round.status === 'cancelled' && (
        <p className="mt-4 rounded-lg border border-casino-border bg-casino-bg p-4 text-sm text-casino-muted">
          Empate persistente — apuestas devueltas.
        </p>
      )}

      {waiting && seated && me && (
        <div className="mt-6">
          {chosen === null ? (
            <div className="flex flex-wrap gap-3">
              {CHOICES.map((c) => (
                <button
                  key={c.value}
                  onClick={() => {
                    setChosen(c.value);
                    play.mutate(c.value);
                  }}
                  disabled={play.isPending}
                  className="rounded-xl border-2 border-casino-gold/60 bg-casino-bg px-6 py-4 text-2xl enabled:hover:scale-105 disabled:opacity-40"
                >
                  {c.label}
                </button>
              ))}
            </div>
          ) : (
            <p className="text-sm text-casino-muted">
              Elegiste {CHOICES.find((c) => c.value === chosen)?.label}. Esperando al resto…
              (elección secreta, ni la API la expone)
            </p>
          )}
          {play.isError && (
            <p role="alert" className="mt-3 text-sm text-casino-red">
              {play.error.message}
            </p>
          )}
        </div>
      )}
    </section>
  );
}
