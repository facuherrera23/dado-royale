import { AnimatePresence, motion } from 'framer-motion';

import { useAuth } from '@/features/auth/useAuth';

import { describeHand, handValue, RESULT_LABELS } from './blackjack';
import { Card } from './Card';
import { useBlackjackAction, type Round, type RoundPlayer } from './useRound';

interface Props {
  tableId: string;
  data: { round: Round | null; players: RoundPlayer[] };
  seated: boolean;
}

/** Panel de blackjack: dealer, manos, hit/stand y resultado por jugador. */
export function BlackjackPanel({ tableId, data, seated }: Props) {
  const { user } = useAuth();
  const action = useBlackjackAction(tableId);

  const round = data.round;
  if (!round) return null;

  const players = data.players;
  const me = players.find((p) => p.user_id === user?.id);
  const iCanPlay = round.status === 'in_progress' && !!me && !me.stood && me.result === null;
  const dealerValue = round.status === 'finished' ? handValue(round.dealer_cards) : null;

  return (
    <section className="rounded-xl border border-casino-gold/40 bg-casino-surface p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">
          Blackjack <span aria-hidden>♠</span>{' '}
          <span className="text-sm font-normal text-casino-muted">
            (contra la banca · natural paga 3:2 · la banca se planta en 17)
          </span>
        </h2>
      </div>

      {/* Dealer */}
      <div className="mt-4 rounded-lg border border-casino-border bg-casino-bg p-4">
        <p className="text-sm font-medium text-casino-muted">
          La banca{dealerValue !== null ? ` · Total: ${String(dealerValue)}` : ''}
        </p>
        <div className="mt-3 flex gap-2">
          {round.dealer_cards.map((c, i) => (
            <Card key={`d-${String(i)}-${String(c)}`} value={c} label={`banca ${String(i + 1)}`} />
          ))}
        </div>
      </div>

      <AnimatePresence>
        {round.status === 'finished' && me?.result && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            role="status"
            className={`mt-4 rounded-lg border p-4 ${
              me.result === 'loss'
                ? 'border-casino-red/50 bg-casino-red/10'
                : me.result === 'push'
                  ? 'border-casino-border bg-casino-bg'
                  : 'border-casino-green/50 bg-casino-green/10'
            }`}
          >
            <p className="font-semibold">
              {RESULT_LABELS[me.result] ?? me.result}
              {me.result === 'win' && ` +${String(me.bet_amount)} 🪙`}
              {me.result === 'blackjack' &&
                ` +${String(me.bet_amount + Math.ceil((me.bet_amount * 3) / 2))} 🪙`}
            </p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Jugadores */}
      <ul className="mt-6 grid gap-3 sm:grid-cols-2">
        {players.map((p) => (
          <li
            key={p.user_id}
            className={`flex flex-col gap-3 rounded-lg border p-4 ${
              p.result === 'win' || p.result === 'blackjack'
                ? 'border-casino-gold bg-casino-gold/10'
                : 'border-casino-border bg-casino-bg'
            }`}
          >
            <div className="flex items-center justify-between">
              <p className="font-medium">
                {p.profiles?.username ?? 'Jugador'}
                {p.user_id === user?.id && (
                  <span className="ml-2 text-xs text-casino-muted">(tú)</span>
                )}
              </p>
              <span className="text-sm text-casino-muted">
                Apuesta: <strong className="text-casino-gold">{p.bet_amount} 🪙</strong>
              </span>
            </div>
            <div className="flex flex-wrap gap-2">
              {p.cards.map((c, i) => (
                <Card
                  key={`${p.user_id}-${String(i)}-${String(c)}`}
                  value={c}
                  label={String(i + 1)}
                />
              ))}
            </div>
            <p className="text-sm text-casino-muted">
              {p.cards.length === 0 ? 'Sin cartas' : describeHand(p)}
              {p.stood && p.result === null ? ' · Plantado' : ''}
              {p.result ? ` · ${RESULT_LABELS[p.result]}` : ''}
            </p>
          </li>
        ))}
      </ul>

      {/* Acciones del jugador */}
      {iCanPlay && (
        <div className="mt-6 flex flex-wrap gap-3">
          {(['hit', 'stand'] as const).map((a) => (
            <button
              key={a}
              onClick={() => {
                action.mutate({ roundId: round.id, action: a });
              }}
              disabled={action.isPending}
              className={`rounded-lg px-8 py-3 text-lg font-bold shadow-lg transition-transform enabled:hover:scale-105 disabled:opacity-50 ${
                a === 'hit'
                  ? 'bg-casino-gold text-black'
                  : 'border border-casino-gold text-casino-gold'
              }`}
            >
              {action.isPending ? '…' : a === 'hit' ? '♠ Pedir carta' : '✋ Plantarse'}
            </button>
          ))}
        </div>
      )}
      {round.status === 'in_progress' && seated && me && (me.stood || me.result) && (
        <p className="mt-6 text-sm text-casino-muted">Esperando al resto de jugadores…</p>
      )}
      {action.isError && (
        <p role="alert" className="mt-4 text-sm text-casino-red">
          {action.error.message}
        </p>
      )}
    </section>
  );
}
