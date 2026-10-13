import { useQuery } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

const PAGE_SIZE = 10;

export interface HandHistoryRow {
  round_id: string;
  hand_no: number;
  bet_amount: number;
  is_winner: boolean;
  result: string | null;
  dice1: number | null;
  dice2: number | null;
  card1: number | null;
  card2: number | null;
  cards: number[];
  rounds: { status: string; created_at: string; tables: { game: string; name: string } | null };
}

/** Historial de manos del usuario (dados, póker y blackjack), paginado. */
export function useHandHistory(page: number) {
  const { user } = useAuth();

  return useQuery({
    queryKey: ['my-hands', user?.id, page],
    enabled: !!user,
    placeholderData: (prev) => prev,
    queryFn: async () => {
      if (!user) throw new Error('sin usuario');
      const from = page * PAGE_SIZE;
      const to = from + PAGE_SIZE - 1;
      const { data, error, count } = await supabase
        .from('round_players')
        .select('*, rounds(status, created_at, tables(game, name))', { count: 'exact' })
        .eq('user_id', user.id)
        .order('round_id', { ascending: false })
        .range(from, to);
      if (error) throw error;
      return { rows: data as unknown as HandHistoryRow[], total: count ?? 0 };
    },
  });
}

export const HANDS_PAGE_SIZE = PAGE_SIZE;
