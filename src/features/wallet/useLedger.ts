import { useEffect } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

export const LEDGER_PAGE_SIZE = 10;

/** Historial paginado del ledger propio, más reciente primero. */
export function useLedgerHistory(page: number) {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['ledger', user?.id, page],
    enabled: !!user,
    placeholderData: (prev) => prev, // evita parpadeo al cambiar de página
    queryFn: async () => {
      if (!user) throw new Error('sin usuario');
      const from = page * LEDGER_PAGE_SIZE;
      const to = from + LEDGER_PAGE_SIZE - 1;
      const { data, error, count } = await supabase
        .from('ledger')
        .select('*', { count: 'exact' })
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .range(from, to);
      if (error) throw error;
      return { rows: data, total: count ?? 0 };
    },
  });

  // Los nuevos movimientos (faucet, apuestas, pagos) refrescan la lista
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel(`ledger-${user.id}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'ledger', filter: `user_id=eq.${user.id}` },
        () => {
          void queryClient.invalidateQueries({ queryKey: ['ledger', user.id] });
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [user, queryClient]);

  return query;
}

/** Fecha del último faucet (para mostrar el cooldown). */
export function useLastFaucet() {
  const { user } = useAuth();
  return useQuery({
    queryKey: ['last-faucet', user?.id],
    enabled: !!user,
    queryFn: async () => {
      if (!user) throw new Error('sin usuario');
      const { data, error } = await supabase
        .from('ledger')
        .select('created_at')
        .eq('user_id', user.id)
        .eq('type', 'faucet')
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data?.created_at ?? null;
    },
  });
}

/** Reclama fichas gratis. El servidor impone el cooldown (errcode P0002). */
export function useClaimFaucet() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('claim_faucet');
      if (error) throw error;
      return data as { balance: number; claimed: number; next_claim_at: string };
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['wallet', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['ledger', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['last-faucet', user?.id] });
    },
  });
}
