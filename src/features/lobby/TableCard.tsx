import { useNavigate } from 'react-router-dom';

import { useAuth } from '@/features/auth/useAuth';
import { useWallet } from '@/features/wallet/useWallet';

import type { TableWithSeated } from './useTables';
import { useJoinTable, useMySeat } from './useTables';

const STATUS_LABEL: Record<string, string> = {
  open: 'Abierta',
  in_round: 'En partida',
  closed: 'Cerrada',
};

/** Tarjeta de una mesa en el lobby. */
export function TableCard({ table }: { table: TableWithSeated }) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { data: wallet } = useWallet();
  const { data: mySeat } = useMySeat();
  const join = useJoinTable();

  const full = table.seated >= table.max_players;
  // En blackjack basta el mínimo para sentarse (la apuesta se fija después)
  const affordable = (wallet?.balance ?? 0) >= table.bet_amount;
  const seatedHere = mySeat === table.id;
  const seatedElsewhere = !!mySeat && !seatedHere;

  const canJoin = table.status === 'open' && !full && affordable && !seatedElsewhere;
  const disabledReason = full
    ? 'Mesa llena'
    : !affordable
      ? 'Saldo insuficiente'
      : seatedElsewhere
        ? 'Estás en otra mesa'
        : table.status !== 'open'
          ? STATUS_LABEL[table.status]
          : null;

  return (
    <article className="flex flex-col gap-4 rounded-xl border border-casino-border bg-casino-surface p-5">
      <div className="flex items-start justify-between">
        <div>
          <h2 className="text-lg font-semibold">{table.name}</h2>
          <p className="text-sm text-casino-muted">{STATUS_LABEL[table.status] ?? table.status}</p>
        </div>
        <span className="rounded-md bg-casino-bg px-3 py-1 text-lg font-bold text-casino-gold">
          {table.game === 'blackjack' && table.max_bet
            ? `${table.bet_amount.toLocaleString('es')}–${table.max_bet.toLocaleString('es')} 🪙`
            : `${table.bet_amount.toLocaleString('es')} 🪙`}
        </span>
      </div>

      <div className="flex items-center justify-between text-sm text-casino-muted">
        <span>
          Jugadores:{' '}
          <strong className="text-casino-text">
            {table.seated}/{table.max_players}
          </strong>
        </span>
        <span aria-hidden>👥</span>
      </div>

      {seatedHere && user ? (
        <button
          onClick={() => void navigate(`/mesa/${table.id}`)}
          className="rounded-md bg-casino-gold px-4 py-2 font-semibold text-black transition-opacity hover:opacity-90"
        >
          Ir a mi mesa →
        </button>
      ) : (
        <button
          onClick={() => {
            join.mutate(table.id, { onSuccess: () => void navigate(`/mesa/${table.id}`) });
          }}
          disabled={!canJoin || join.isPending}
          className="rounded-md bg-casino-green px-4 py-2 font-semibold text-white transition-opacity enabled:hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {join.isPending
            ? 'Uniendo…'
            : (disabledReason ?? `Unirse por ${String(table.bet_amount)} 🪙`)}
        </button>
      )}
    </article>
  );
}
