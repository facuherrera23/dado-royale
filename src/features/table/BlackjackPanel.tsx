import { useEffect, useRef } from 'react';

import { AnimatePresence, motion } from 'framer-motion';

import { useAuth } from '@/features/auth/useAuth';
import { useWallet } from '@/features/wallet/useWallet';
import { playCard, playLose, playWin } from '@/lib/sounds';

import { cardRank, describeHand, handValue, RESULT_LABELS } from './blackjack';
import { Card } from './Card';
import { ChipsBurst } from './ChipsBurst';
import { useBlackjackAction, type Round, type RoundPlayer } from './useRound';

type BjAction = 'hit' | 'stand' | 'double' | 'insurance' | 'split';

interface Props {
  tableId: string;
  data: { round: Round | null; players: RoundPlayer[] };
  seated: boolean;
}

/** Panel de blackjack: banca con carta oculta, manos (con split), acciones completas. */
export function BlackjackPanel({ tableId, data, seated }: Props) {
  const { user } = useAuth();
  const { data: wallet } = useWallet();
  const action = useBlackjackAction(tableId);

  const round = data.round;

  // Sonidos al liquidar la mano (una vez por ronda)
  const playedSound = useRef<string | null>(null);
  useEffect(() => {
    if (!round || round.status !== 'finished' || playedSound.current === round.id) return;
    playedSound.current = round.id;
    const mine = data.players.filter((p) => p.user_id === user?.id);
    if (mine.some((h) => h.result === 'win' || h.result === 'blackjack')) playWin();
    else if (mine.some((h) => h.result === 'loss')) playLose();
  }, [round, data.players, user?.id]);

  if (!round) return null;

  const players = data.players;
  const myHands = players
    .filter((p) => p.user_id === user?.id)
    .sort((a, b) => a.hand_no - b.hand_no);
  const finished = round.status === 'finished';
  const dealerUpcardIsAce = round.dealer_cards.length > 0 && cardRank(round.dealer_cards[0]) === 14;
  const dealerValue = finished ? handValue(round.dealer_cards) : null;

  // Agrupar manos por jugador manteniendo el orden
  const byPlayer = new Map<string, RoundPlayer[]>();
  for (const p of players) {
    byPlayer.set(p.user_id, [...(byPlayer.get(p.user_id) ?? []), p]);
  }

  const canInsure =
    round.status === 'in_progress' &&
    myHands.length === 1 &&
    myHands[0] &&
    !myHands[0].stood &&
    myHands[0].cards.length === 2 &&
    myHands[0].insurance === null &&
    dealerUpcardIsAce;

  const canSplit =
    round.status === 'in_progress' &&
    myHands.length === 1 &&
    myHands[0] &&
    !myHands[0].stood &&
    myHands[0].cards.length === 2 &&
    myHands[0].insurance === null &&
    cardRank(myHands[0].cards[0]) === cardRank(myHands[0].cards[1]) &&
    (wallet?.balance ?? 0) >= myHands[0].bet_amount;

  const act = (a: BjAction, hand?: number) => {
    if (a === 'hit') playCard();
    action.mutate({ roundId: round.id, action: a, hand });
  };

  return (
    <section className="rounded-xl border border-casino-gold/40 bg-casino-surface p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">
          Blackjack <span aria-hidden>♠</span>{' '}
          <span className="text-sm font-normal text-casino-muted">
            (banca se planta en 17 · natural 3:2 · doblar/separar/seguro)
          </span>
        </h2>
      </div>

      {/* Banca: solo la primera carta visible hasta el final */}
      <div className="mt-4 rounded-lg border border-casino-border bg-casino-bg p-4">
        <p className="text-sm font-medium text-casino-muted">
          La banca{dealerValue !== null ? ` · Total: ${String(dealerValue)}` : ''}
        </p>
        <div className="mt-3 flex gap-2">
          {round.dealer_cards.map((c, i) => (
            <Card
              key={`d-${String(i)}-${String(finished ? c : i === 0 ? c : null)}`}
              value={c}
              label={`banca ${String(i + 1)}`}
            />
          ))}
          {/* Carta oculta de la banca (real: ni la API ni Realtime la exponen) */}
          {!finished && round.dealer_cards.length > 0 && <Card value={null} label="banca oculta" />}
        </div>
        {!finished && dealerUpcardIsAce && (
          <p className="mt-2 text-xs text-casino-gold">
            La banca muestra un As — seguro disponible
          </p>
        )}
      </div>

      <AnimatePresence>
        {finished && myHands.length > 0 && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            role="status"
            className="relative mt-4 flex flex-col gap-2 overflow-hidden"
          >
            {myHands.some((h) => h.result === 'win' || h.result === 'blackjack') && <ChipsBurst />}
            {myHands.map((h) => (
              <div
                key={h.hand_no}
                className={`rounded-lg border p-4 ${
                  h.result === 'loss'
                    ? 'border-casino-red/50 bg-casino-red/10'
                    : h.result === 'push'
                      ? 'border-casino-border bg-casino-bg'
                      : 'border-casino-green/50 bg-casino-green/10'
                }`}
              >
                <p className="font-semibold">
                  {myHands.length > 1 && `Mano ${String(h.hand_no)}: `}
                  {h.result ? (RESULT_LABELS[h.result] ?? h.result) : ''}
                  {h.result === 'win' && ` +${String(h.bet_amount)} 🪙`}
                  {h.result === 'blackjack' && ` +${String(Math.ceil((h.bet_amount * 3) / 2))} 🪙`}
                </p>
              </div>
            ))}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Jugadores (cada jugador puede tener mano 1 y 2 tras separar) */}
      <ul className="mt-6 grid gap-3 sm:grid-cols-2">
        {[...byPlayer.values()].map((hands) => {
          const first = hands[0];
          return (
            <li
              key={first.user_id}
              className={`flex flex-col gap-3 rounded-lg border p-4 ${
                hands.some((h) => h.result === 'win' || h.result === 'blackjack')
                  ? 'border-casino-gold bg-casino-gold/10'
                  : 'border-casino-border bg-casino-bg'
              }`}
            >
              <div className="flex items-center justify-between">
                <p className="font-medium">
                  {first.profiles?.username ?? 'Jugador'}
                  {first.user_id === user?.id && (
                    <span className="ml-2 text-xs text-casino-muted">(tú)</span>
                  )}
                </p>
                {first.insurance !== null && (
                  <span className="text-xs text-casino-muted">asegurado {first.insurance} 🪙</span>
                )}
              </div>

              {hands
                .sort((a, b) => a.hand_no - b.hand_no)
                .map((h) => (
                  <div key={h.hand_no} className="rounded-md border border-casino-border/60 p-2">
                    <div className="flex items-center justify-between text-xs text-casino-muted">
                      <span>
                        {hands.length > 1 && `Mano ${String(h.hand_no)} · `}Apuesta:{' '}
                        <strong className="text-casino-gold">{h.bet_amount} 🪙</strong>
                      </span>
                      <span>{describeHand(h)}</span>
                    </div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {h.cards.map((c, i) => (
                        <Card
                          key={`${h.user_id}-${String(h.hand_no)}-${String(i)}-${String(c)}`}
                          value={c}
                          label={String(i + 1)}
                        />
                      ))}
                    </div>

                    {h.user_id === user?.id && !finished && !h.stood && h.result === null && (
                      <div className="mt-3 flex flex-wrap gap-2">
                        <button
                          onClick={() => {
                            act('hit', h.hand_no);
                          }}
                          disabled={action.isPending}
                          className="rounded-lg bg-casino-gold px-5 py-2 font-bold text-black enabled:hover:scale-105 disabled:opacity-50"
                        >
                          ♠ Pedir carta
                        </button>
                        <button
                          onClick={() => {
                            act('stand', h.hand_no);
                          }}
                          disabled={action.isPending}
                          className="rounded-lg border border-casino-gold px-5 py-2 font-bold text-casino-gold enabled:hover:scale-105 disabled:opacity-50"
                        >
                          ✋ Plantarse
                        </button>
                        {h.cards.length === 2 && (
                          <button
                            onClick={() => {
                              act('double', h.hand_no);
                            }}
                            disabled={action.isPending}
                            title="Doblas la apuesta, recibes una carta y te plantas"
                            className="rounded-lg border border-casino-green px-5 py-2 font-bold text-casino-green enabled:hover:scale-105 disabled:opacity-50"
                          >
                            ×2 Doblar
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                ))}
            </li>
          );
        })}
      </ul>

      {/* Acciones especiales (una vez): seguro y separar */}
      {seated && !finished && (canInsure || canSplit) && (
        <div className="mt-4 flex flex-wrap gap-2">
          {canInsure && myHands[0] && (
            <button
              onClick={() => {
                act('insurance');
              }}
              disabled={action.isPending}
              className="rounded-md border border-casino-gold/60 px-4 py-2 text-sm font-semibold text-casino-gold enabled:hover:bg-casino-gold/10 disabled:opacity-40"
            >
              🛡️ Asegurar por {String(Math.floor(myHands[0].bet_amount / 2))} 🪙
            </button>
          )}
          {canSplit && (
            <button
              onClick={() => {
                act('split');
              }}
              disabled={action.isPending}
              className="rounded-md border border-casino-gold/60 px-4 py-2 text-sm font-semibold text-casino-gold enabled:hover:bg-casino-gold/10 disabled:opacity-40"
            >
              ⚔️ Separar el par
            </button>
          )}
        </div>
      )}

      {action.isError && (
        <p role="alert" className="mt-4 text-sm text-casino-red">
          {action.error.message}
        </p>
      )}
    </section>
  );
}
