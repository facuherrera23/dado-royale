import { useNavigate, useParams, Link } from 'react-router-dom';

import { useAuth } from '@/features/auth/useAuth';
import { useLeaveTable, useTablePlayers, useTables } from '@/features/lobby/useTables';
import { useConfig } from '@/lib/useConfig';

import { Avatar } from '@/components/Avatar';

import { RoundPanel } from './RoundPanel';
import { BetSetter } from './BetSetter';
import { ChatPanel } from './ChatPanel';
import { useSeatNotifications } from './useTableNotifications';
import { useCurrentRound, useRoundHistory, useStartRound } from './useRound';

/**
 * Vista de una mesa: jugadores sentados, ronda activa con dados en
 * tiempo real, historial de la mesa y botón de salida.
 */
export function TablePage() {
  const { id: tableId } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  useSeatNotifications(tableId);
  const { data: tables } = useTables();
  const { data: players, isLoading } = useTablePlayers(tableId);
  const { data: roundData, isLoading: loadingRound } = useCurrentRound(tableId);
  const { data: history } = useRoundHistory(tableId);
  const { data: config } = useConfig();
  const leave = useLeaveTable();
  const start = useStartRound(tableId);

  const minPlayers = config?.get('min_players') ?? 2;
  const table = tables?.find((t) => t.id === tableId);
  const seated = !!players?.some((p) => p.user_id === user?.id);
  const seatedCount = players?.length ?? 0;
  const roundActive = !!roundData?.round && roundData.round.status === 'in_progress';
  const potentialPot = table ? table.bet_amount * seatedCount : 0;

  const betRangeText =
    table != null && table.max_bet != null
      ? `${String(table.bet_amount)}–${String(table.max_bet)}`
      : '';

  return (
    <main className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">{table?.name ?? 'Mesa'}</h1>
          <p className="mt-1 text-sm text-casino-muted">
            {table?.game === 'blackjack' ? (
              <>
                Apuesta variable:{' '}
                <strong className="text-casino-gold">
                  {table.bet_amount}–{table.max_bet ?? 0} 🪙
                </strong>
                {' · '}Contra la banca · Natural paga 3:2 · Se planta en 17
              </>
            ) : (
              <>
                Apuesta fija:{' '}
                <strong className="text-casino-gold">{table?.bet_amount ?? '…'} 🪙</strong>
                {' · '}Comisión de la casa 4% del pozo
                {table ? `: ~${String(Math.floor((potentialPot * 4) / 100))} 🪙` : ''}
              </>
            )}
          </p>
        </div>
        {seated && !roundActive && (
          <button
            onClick={() => {
              if (!tableId) return;
              leave.mutate(tableId, { onSuccess: () => void navigate('/lobby') });
            }}
            disabled={leave.isPending}
            className="rounded-md border border-casino-border px-4 py-2 text-sm text-casino-muted transition-colors hover:border-casino-red hover:text-casino-red disabled:opacity-40"
          >
            {leave.isPending ? 'Saliendo…' : 'Salir de la mesa'}
          </button>
        )}
      </div>

      {(leave.isError || start.isError) && (
        <p
          role="alert"
          className="rounded-md border border-casino-red/50 bg-casino-red/10 p-3 text-sm text-casino-red"
        >
          {leave.error?.message ?? start.error?.message}
        </p>
      )}

      {/* Ronda activa o recién terminada */}
      {roundData?.round && tableId && table && (
        <RoundPanel
          tableId={tableId}
          tableName={table.name}
          betAmount={table.bet_amount}
          game={table.game}
          data={{ round: roundData.round, players: roundData.players }}
          seated={seated}
          seatedCount={seatedCount}
        />
      )}
      {loadingRound && <p className="animate-pulse text-casino-muted">Cargando ronda…</p>}

      {/* Sala de espera: botón de inicio */}
      {!roundData?.round && (
        <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
          <h2 className="text-lg font-semibold">
            Jugadores sentados ({seatedCount}/{table?.max_players ?? '…'})
          </h2>
          {isLoading && <p className="mt-4 animate-pulse text-casino-muted">Cargando…</p>}
          {players && players.length === 0 && (
            <p className="mt-4 text-casino-muted">Nadie sentado todavía.</p>
          )}
          <ul className="mt-4 grid gap-2 sm:grid-cols-2">
            {players?.map((p) => (
              <li
                key={p.user_id}
                className="flex items-center gap-3 rounded-lg border border-casino-border bg-casino-bg px-4 py-3"
              >
                <Avatar username={p.profiles.username} avatarUrl={p.profiles.avatar_url} />
                <span className="font-medium">
                  {p.profiles.username}
                  {p.user_id === user?.id && (
                    <span className="ml-2 text-xs text-casino-muted">(tú)</span>
                  )}
                </span>
              </li>
            ))}
          </ul>

          <div className="mt-6 flex flex-col gap-4">
            {seated && table?.game === 'blackjack' && tableId && (
              <BetSetter
                tableId={tableId}
                min={table.bet_amount}
                max={table.max_bet ?? table.bet_amount}
                current={players?.find((p) => p.user_id === user?.id)?.pending_bet ?? null}
              />
            )}
            {seated ? (
              table?.game === 'blackjack' ? (
                players?.find((p) => p.user_id === user?.id)?.pending_bet ? (
                  <button
                    onClick={() => {
                      start.mutate();
                    }}
                    disabled={start.isPending}
                    className="self-start rounded-lg bg-casino-green px-8 py-3 text-lg font-bold text-white shadow-lg transition-transform enabled:hover:scale-105 disabled:opacity-50"
                  >
                    {start.isPending ? 'Repartiendo…' : '▶ Repartir cartas'}
                  </button>
                ) : (
                  <p className="text-sm text-casino-muted">
                    Fija tu apuesta entre {betRangeText} 🪙 para entrar en la siguiente mano.
                  </p>
                )
              ) : seatedCount >= minPlayers ? (
                <button
                  onClick={() => {
                    start.mutate();
                  }}
                  disabled={start.isPending}
                  className="self-start rounded-lg bg-casino-green px-8 py-3 text-lg font-bold text-white shadow-lg transition-transform enabled:hover:scale-105 disabled:opacity-50"
                >
                  {start.isPending
                    ? 'Creando ronda…'
                    : `▶ Iniciar ronda (${String(table?.bet_amount ?? 0)} 🪙 por jugador)`}
                </button>
              ) : (
                <p className="text-sm text-casino-muted">
                  Se necesitan al menos {minPlayers} jugadores sentados para iniciar la ronda.
                </p>
              )
            ) : (
              <button
                onClick={() => void navigate('/lobby')}
                className="rounded-md border border-casino-border px-4 py-2 text-sm text-casino-muted hover:text-casino-text"
              >
                No estás sentado — vuelve al lobby para unirte
              </button>
            )}
          </div>
        </section>
      )}

      {/* Chat + spectator indicator */}
      {tableId && table && (
        <div className="grid gap-4 lg:grid-cols-[2fr_1fr]">
          <ChatPanel tableId={tableId} seated={seated} />
          <div className="rounded-xl border border-casino-border bg-casino-surface p-4 text-sm text-casino-muted">
            <p className="font-semibold text-casino-text">👀 Espectadores</p>
            <p className="mt-2">
              {seated
                ? '⚔️ Estás jugando.'
                : '👀 Estás viendo esta mesa como espectador (no juegas ni apuestas).'}
            </p>
            {history && history.length > 0 && (
              <Link
                to={`/replay/${history[0].id}`}
                className="mt-3 inline-block text-casino-gold underline"
              >
                🔁 Ver replay de la última ronda
              </Link>
            )}
          </div>
        </div>
      )}

      {/* Historial de la mesa */}
      <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <h2 className="text-lg font-semibold">Historial de la mesa</h2>
        {history && history.length === 0 && (
          <p className="mt-3 text-sm text-casino-muted">Aún no se ha jugado ninguna ronda.</p>
        )}
        {history && history.length > 0 && (
          <ul className="mt-3 divide-y divide-casino-border/50 text-sm">
            {history.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <span className="text-casino-muted">
                  {new Date(r.created_at).toLocaleString('es')}
                </span>
                {r.status === 'finished' ? (
                  <span>
                    🏆 {r.profiles?.username ?? '—'} ganó{' '}
                    <strong className="text-casino-green">
                      {(r.pot - r.house_fee).toLocaleString('es')} 🪙
                    </strong>
                    <span className="text-casino-muted"> (casa: {r.house_fee} 🪙)</span>
                  </span>
                ) : (
                  <span className="text-casino-muted">Ronda cancelada — apuestas devueltas</span>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}
