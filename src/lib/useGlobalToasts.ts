import { useEffect } from 'react';

import { useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';
import { toast } from '@/lib/toastStore';

const NOTIFY_LABELS: Record<string, string> = {
  payout: '💰 ¡Te pagaron!',
  refund: '↩️ Apuesta devuelta',
  faucet: '🎁 Fichas gratis recibidas',
  prize: '🏆 ¡Premio de torneo!',
};

/**
 * Canal realtime ÚNICO por usuario (wallet + ledger):
 *  - invalida las queries afectadas (saldo, historial)
 *  - lanza toasts en pagos/devoluciones/premios
 * Se monta una vez (AppShell) para evitar canales duplicados.
 */
export function useGlobalToasts() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel(`user-sync-${user.id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'wallets', filter: `user_id=eq.${user.id}` },
        () => {
          void queryClient.invalidateQueries({ queryKey: ['wallet', user.id] });
        },
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'ledger', filter: `user_id=eq.${user.id}` },
        (payload) => {
          void queryClient.invalidateQueries({ queryKey: ['ledger', user.id] });
          void queryClient.invalidateQueries({ queryKey: ['wallet', user.id] });
          const row = payload.new as { type: string; amount: number };
          const label = NOTIFY_LABELS[row.type];
          if (!label) return;
          const sign =
            row.amount >= 0
              ? `+${row.amount.toLocaleString('es')}`
              : row.amount.toLocaleString('es');
          toast(
            row.type === 'payout' || row.type === 'prize' ? 'success' : 'info',
            `${label} ${sign} 🪙`,
          );
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [user, queryClient]);
}
