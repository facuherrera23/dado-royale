import { useQuery } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

const WALLET_KEY = 'wallet';

/**
 * Saldo del usuario autenticado.
 * El refresco realtime lo centraliza useGlobalToasts (canal único por usuario),
 * que invalida ['wallet', user.id] y ['ledger', user.id].
 */
export function useWallet() {
  const { user } = useAuth();

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

  return query;
}
