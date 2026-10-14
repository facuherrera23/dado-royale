import { z } from 'zod';

import { useQuery } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

import { KycQueue } from './KycQueue';
import { FraudPanel } from './FraudPanel';

const adminStatsSchema = z.object({
  house_balance: z.number(),
  total_fees: z.number(),
  total_rounds: z.number(),
  finished_rounds: z.number(),
  cancelled_rounds: z.number(),
  total_faucet_given: z.number(),
  total_payouts: z.number(),
  registered_users: z.number(),
});

/**
 * Panel de administración.
 * La protección real está en el servidor (get_admin_stats exige is_admin,
 * y RLS solo muestra house_account/ledger completo a admins); aquí solo
 * ocultamos la entrada en la UI.
 */
export function AdminPage() {
  const { profile } = useAuth();

  const stats = useQuery({
    queryKey: ['admin-stats'],
    enabled: profile?.is_admin === true,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_admin_stats');
      if (error) throw error;
      return adminStatsSchema.parse(data);
    },
  });

  const recentRounds = useQuery({
    queryKey: ['admin-rounds'],
    enabled: profile?.is_admin === true,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('rounds')
        .select('*, tables(name), profiles!rounds_winner_id_fkey(username)')
        .order('created_at', { ascending: false })
        .limit(20);
      if (error) throw error;
      return data;
    },
  });

  const recentLedger = useQuery({
    queryKey: ['admin-ledger'],
    enabled: profile?.is_admin === true,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('ledger')
        .select('*, profiles(username)')
        .order('created_at', { ascending: false })
        .limit(50);
      if (error) throw error;
      return data;
    },
  });

  if (!profile?.is_admin) {
    return (
      <main>
        <h1 className="text-2xl font-bold text-casino-red">Acceso restringido</h1>
        <p className="mt-2 text-casino-muted">Esta sección es solo para administradores.</p>
      </main>
    );
  }

  return (
    <main className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold">🛡️ Administración</h1>

      <KycQueue />
      <FraudPanel />

      {stats.data && (
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {(
            [
              ['Balance de la casa', stats.data.house_balance],
              ['Comisiones totales', stats.data.total_fees],
              [
                'Rondas (fin./canc.)',
                `${String(stats.data.finished_rounds)} / ${String(stats.data.cancelled_rounds)}`,
              ],
              ['Usuarios registrados', stats.data.registered_users],
              ['Faucet repartido', stats.data.total_faucet_given],
              ['Premios pagados', stats.data.total_payouts],
            ] as const
          ).map(([label, value]) => (
            <div
              key={label}
              className="rounded-xl border border-casino-border bg-casino-surface p-4"
            >
              <p className="text-xs text-casino-muted">{label}</p>
              <p className="mt-1 text-xl font-bold text-casino-gold">
                {typeof value === 'number' ? value.toLocaleString('es') : value}
              </p>
            </div>
          ))}
        </section>
      )}
      {stats.isError && (
        <p role="alert" className="text-casino-red">
          No se pudieron cargar las estadísticas.
        </p>
      )}

      {recentLedger.data && (
        <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
          <h2 className="text-lg font-semibold">Últimos movimientos (todos los usuarios)</h2>
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-casino-border text-left text-casino-muted">
                  <th className="py-2 pr-4 font-medium">Fecha</th>
                  <th className="py-2 pr-4 font-medium">Usuario</th>
                  <th className="py-2 pr-4 font-medium">Tipo</th>
                  <th className="py-2 text-right font-medium">Importe</th>
                </tr>
              </thead>
              <tbody>
                {recentLedger.data.map((row) => (
                  <tr key={row.id} className="border-b border-casino-border/50">
                    <td className="py-2 pr-4 text-casino-muted">
                      {new Date(row.created_at).toLocaleString('es')}
                    </td>
                    <td className="py-2 pr-4">{row.profiles?.username ?? '🏦 casa'}</td>
                    <td className="py-2 pr-4">{row.type}</td>
                    <td
                      className={`py-2 text-right font-semibold ${
                        row.amount >= 0 ? 'text-casino-green' : 'text-casino-red'
                      }`}
                    >
                      {row.amount >= 0 ? '+' : ''}
                      {row.amount.toLocaleString('es')}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {recentRounds.data && (
        <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
          <h2 className="text-lg font-semibold">Rondas recientes</h2>
          <ul className="mt-4 divide-y divide-casino-border/50 text-sm">
            {recentRounds.data.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <span className="text-casino-muted">
                  {new Date(r.created_at).toLocaleString('es')}
                </span>
                <span>{r.tables.name}</span>
                <span>{r.status}</span>
                <span>
                  Pozo {r.pot} 🪙 · Casa {r.house_fee} 🪙 ·{' '}
                  {r.profiles?.username ? `🏆 ${r.profiles.username}` : '—'}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </main>
  );
}
