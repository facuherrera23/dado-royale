import { useEffect } from 'react';

import { useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

const WALLET_KEY = 'wallet';

/**
 * Saldo del usuario autenticado.
 * Combina la consulta inicial con un canal Realtime (la wallet solo se
 * actualiza en el servidor; RLS garantiza que solo recibimos la nuestra).
 */
export function useWallet() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: [WALLET_KEY, user?.id],
    enabled: !!user,
    queryFn: async () => {
      if (!user) throw new Error('sin usuario');
      const { data, error } = await supabase
        .from('wallets')
        .select('*')
        .eq('user_id', user.id)
        .single();
      if (error) throw error;
      return data;
    },
  });

  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel(`wallet-${user.id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'wallets', filter: `user_id=eq.${user.id}` },
        () => {
          void queryClient.invalidateQueries({ queryKey: [WALLET_KEY, user.id] });
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [user, queryClient]);

  return query;
}
