import { useEffect, useState, useRef } from 'react';

import { AnimatePresence, motion } from 'framer-motion';

import { useAuth } from '@/features/auth/useAuth';
import { useConfig } from '@/lib/useConfig';
import { playCard, playDice, playLose, playWin } from '@/lib/sounds';

import { Card } from './Card';
import { Dice } from './Dice';
import { ChipsBurst } from './ChipsBurst';
import { BlackjackPanel } from './BlackjackPanel';
import { RpsPanel } from './RpsPanel';
import { useCancelRound, useRollRound, type Round, type RoundPlayer } from './useRound';

interface Props {
  tableId: string;
  tableName: string;
  betAmount: number;
  game: string;
  data: { round: Round | null; players: RoundPlayer[] };
  seated: boolean;
  seatedCount: number;
}

/** Panel de la ronda activa: dados, pozo comisionado, desempates y resultado. */
export function RoundPanel({ tableId, game, data, seated }: Props) {
  const { user } = useAuth();
  const { data: config } = useConfig();
  const houseFeePct = config?.get('house_fee_percent') ?? 4;
  const round = data.round;

  // Sonido + animación al terminar la ronda (hooks antes de cualquier return)
  const playedSound = useRef<string | null>(null);
  useEffect(() => {
    if (!round || round.status !== 'finished' || playedSound.current === round.id) return;
    playedSound.current = round.id;
    if (round.winner_id === user?.id) playWin();
    else playLose();
  }, [round, user?.id]);
  const iJustWon = !!round && round.status === 'finished' && round.winner_id === user?.id;

  if (game === 'blackjack') {
    return <BlackjackPanel tableId={tableId} data={data} seated={seated} />;
  }
  if (game === 'rps') {
    return <RpsPanel tableId={tableId} data={data} seated={seated} />;
  }
  if (!round) return null;

  const players = data.players;
  const me = players.find((p) => p.user_id === user?.id);
  const played = (p: RoundPlayer) => (game === 'dice' ? p.dice1 !== null : p.card1 !== null);
  const iMustRoll = !!me && !played(me);
  const waitingFor = players.filter((p) => !played(p));
  const rolling = round.status === 'in_progress' && waitingFor.length > 0;
  const inTiebreak = players.some((p) => p.tiebreak_attempts > 0 && !played(p));

  const prize = round.pot - round.house_fee;

  return (
    <section className="rounded-xl border border-casino-gold/40 bg-casino-surface p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">
          Ronda en curso{' '}
          <span aria-hidden>{game === 'dice' ? '🎲' : game === 'war' ? '🗡️' : '🃏'}</span>
        </h2>
        <p className="text-sm text-casino-muted">
          Pozo: <strong className="text-casino-gold">{round.pot.toLocaleString('es')} 🪙</strong>
          {' · '}Comisión de la casa {houseFeePct}%:{' '}
          <strong>{round.house_fee || Math.floor((round.pot * houseFeePct) / 100)} 🪙</strong>
          {' · '}Premio al ganador:{' '}
          <strong className="text-casino-green">
            {(
              round.pot - (round.house_fee || Math.floor((round.pot * houseFeePct) / 100))
            ).toLocaleString('es')}{' '}
            🪙
          </strong>
        </p>
      </div>

      <AnimatePresence>
        {round.status === 'finished' && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            className="relative mt-4 overflow-hidden rounded-lg border border-casino-green/50 bg-casino-green/10 p-4"
            role="status"
          >
            {iJustWon && <ChipsBurst />}
            {round.winner_id === user?.id ? (
              <p className="font-semibold text-casino-green">
                🏆 ¡Has ganado {prize.toLocaleString('es')} fichas!
              </p>
            ) : (
              <p>
                🏆 Ganador:{' '}
                <strong>
                  {players.find((p) => p.user_id === round.winner_id)?.profiles?.username ?? '—'}
                </strong>{' '}
                ({prize.toLocaleString('es')} 🪙 tras la comisión del {houseFeePct}%)
              </p>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {inTiebreak && (
        <p
          className="mt-4 rounded-lg border border-casino-gold/40 bg-casino-gold/10 p-3 text-sm text-casino-gold"
          role="status"
        >
          ⚔️ ¡Empate! Solo los empatados{' '}
          {game === 'dice' ? 'vuelven a lanzar' : 'reciben cartas nuevas'}.
        </p>
      )}

      <ul className="mt-6 grid gap-3 sm:grid-cols-2">
        {players.map((p) => (
          <li
            key={p.user_id}
            className={`flex items-center justify-between gap-4 rounded-lg border p-4 ${
              p.is_winner
                ? 'border-casino-gold bg-casino-gold/10'
                : 'border-casino-border bg-casino-bg'
            }`}
          >
            <div>
              <p className="font-medium">
                {p.profiles?.username ?? 'Jugador'}
                {p.user_id === user?.id && (
                  <span className="ml-2 text-xs text-casino-muted">(tú)</span>
                )}
              </p>
              <p className="text-sm text-casino-muted">
                {!played(p)
                  ? game === 'dice'
                    ? 'Aún no ha lanzado'
                    : game === 'war'
                      ? 'Aún no tiene carta'
                      : 'Aún no tiene cartas'
                  : game === 'dice'
                    ? `Total: ${String(p.total)}`
                    : game === 'war'
                      ? 'Carta revelada'
                      : handLabel(p.card1, p.card2)}
              </p>
            </div>
            <div className="flex gap-2">
              {game === 'dice' ? (
                <>
                  <Dice value={p.dice1} label="1" />
                  <Dice value={p.dice2} label="2" />
                </>
              ) : game === 'war' ? (
                <Card value={p.card1} label="1" />
              ) : (
                <>
                  <Card value={p.card1} label="1" />
                  <Card value={p.card2} label="2" />
                </>
              )}
            </div>
          </li>
        ))}
      </ul>

      {rolling && seated && (
        <div className="mt-6 flex flex-col items-start gap-3">
          {iMustRoll ? (
            <RollButton {...{ tableId, roundId: round.id, game }} />
          ) : (
            <p className="text-sm text-casino-muted">
              Ya jugaste. Esperando a{' '}
              {waitingFor.map((p) => p.profiles?.username ?? 'otro jugador').join(', ')}…
            </p>
          )}
        </div>
      )}

      <CancelControls
        roundId={round.id}
        createdAt={(round as { created_at: string }).created_at}
        tableId={tableId}
      />
    </section>
  );
}

/** Etiqueta legible de una mano de póker 2 cartas. */
function handLabel(c1: number | null, c2: number | null): string {
  if (c1 === null || c2 === null) return 'Sin cartas';
  const r1 = ((c1 - 1) % 13) + 2;
  const r2 = ((c2 - 1) % 13) + 2;
  const name = (r: number) => ({ 11: 'J', 12: 'Q', 13: 'K', 14: 'A' })[r] ?? String(r);
  if (r1 === r2) return `¡Pareja de ${name(r1)}!`;
  return `Carta alta ${name(Math.max(r1, r2))}`;
}

function RollButton({
  tableId,
  roundId,
  game,
}: {
  tableId: string;
  roundId: string;
  game: string;
}) {
  const roll = useRollRound(tableId);
  const label =
    game === 'dice' ? '🎲 Tirando…' : game === 'war' ? '🗡️ Robando…' : '🃏 Repartiendo…';
  const labelIdle =
    game === 'dice'
      ? '🎲 ¡Tirar mis dados!'
      : game === 'war'
        ? '🗡️ ¡Robar mi carta!'
        : '🃏 ¡Repartir mis cartas!';
  return (
    <>
      <button
        onClick={() => {
          if (game === 'dice') playDice();
          else playCard();
          roll.mutate(roundId);
        }}
        disabled={roll.isPending}
        className="rounded-lg bg-casino-gold px-8 py-3 text-lg font-bold text-black shadow-lg transition-transform enabled:hover:scale-105 disabled:opacity-50"
      >
        {roll.isPending ? label : labelIdle}
      </button>
      {roll.isError && (
        <p role="alert" className="text-sm text-casino-red">
          {roll.error.message}
        </p>
      )}
    </>
  );
}

function CancelControls({
  roundId,
  createdAt,
  tableId,
}: {
  roundId: string;
  createdAt: string;
  tableId: string;
}) {
  const cancel = useCancelRound(tableId);
  const { data: config } = useConfig();
  const timeoutSec = config?.get('round_timeout_seconds') ?? 300;

  // Reloj interno para habilitar el botón de cancelación al vencer el timeout
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => {
      setNow(Date.now());
    }, 5000);
    return () => {
      clearInterval(id);
    };
  }, []);

  const canCancelAt = new Date(createdAt).getTime() + timeoutSec * 1000;
  if (now < canCancelAt) return null;

  return (
    <div className="mt-4">
      <button
        onClick={() => {
          cancel.mutate(roundId);
        }}
        disabled={cancel.isPending}
        className="rounded-md border border-casino-border px-4 py-2 text-sm text-casino-muted transition-colors hover:border-casino-red hover:text-casino-red disabled:opacity-40"
      >
        Cancelar ronda y reembolsar apuestas
      </button>
      {cancel.isError && (
        <p role="alert" className="mt-2 text-sm text-casino-red">
          {cancel.error.message}
        </p>
      )}
    </div>
  );
}
