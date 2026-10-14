import { useEffect } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';
import type { Tables } from '@/types/database.types';

export type Round = Tables<'rounds'>;
export type RoundPlayer = Tables<'round_players'> & {
  profiles: { username: string; avatar_url: string | null } | null;
};

const ROUND_KEY = 'current-round';

/** Ronda activa (o la más reciente) de una mesa, con sus jugadores, en tiempo real. */
export function useCurrentRound(tableId: string | undefined) {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: [ROUND_KEY, tableId],
    enabled: !!tableId,
    queryFn: async () => {
      // Traemos las 2 últimas rondas: la activa (si hay) y, al terminar,
      // la recién cerrada para enseñar el resultado durante ~60s.
      const { data: rounds, error } = await supabase
        .from('rounds')
        .select('*')
        .eq('table_id', tableId ?? '')
        .order('created_at', { ascending: false })
        .limit(2);
      if (error) throw error;

      const active = rounds.find((r) => r.status === 'waiting' || r.status === 'in_progress');
      let show = active ?? null;
      if (!show && rounds[0]) {
        const closed = rounds[0];
        const finishedAt = closed.finished_at ? new Date(closed.finished_at).getTime() : 0;
        if (Date.now() - finishedAt < 60_000) show = closed;
      }
      if (!show) return { round: null, players: [] as RoundPlayer[] };

      const { data: players, error: e2 } = await supabase
        .from('round_players')
        .select('*, profiles(username, avatar_url)')
        .eq('round_id', show.id);
      if (e2) throw e2;
      return { round: show, players };
    },
  });

  useEffect(() => {
    if (!tableId) return;
    const channel = supabase
      .channel(`round-${tableId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rounds', filter: `table_id=eq.${tableId}` },
        () => {
          void queryClient.invalidateQueries({ queryKey: [ROUND_KEY, tableId] });
          void queryClient.invalidateQueries({ queryKey: ['round-history', tableId] });
        },
      )
      .on('postgres_changes', { event: '*', schema: 'public', table: 'round_players' }, () => {
        void queryClient.invalidateQueries({ queryKey: [ROUND_KEY, tableId] });
      })
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [tableId, queryClient]);

  return query;
}

/** Historial de rondas terminadas de la mesa (últimas 10). */
export function useRoundHistory(tableId: string | undefined) {
  return useQuery({
    queryKey: ['round-history', tableId],
    enabled: !!tableId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('rounds')
        .select('*, profiles!rounds_winner_id_fkey(username)')
        .eq('table_id', tableId ?? '')
        .in('status', ['finished', 'cancelled'])
        .order('created_at', { ascending: false })
        .limit(10);
      if (error) throw error;
      return data;
    },
  });
}

/** Crea la ronda y bloquea las apuestas (una transacción en el servidor). */
export function useStartRound(tableId: string | undefined) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('start_round', { p_table_id: tableId ?? '' });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [ROUND_KEY, tableId] });
      void queryClient.invalidateQueries({ queryKey: ['tables'] });
    },
  });
}

/** Lanza los dados del jugador actual en la ronda. */
export function useRollRound(tableId: string | undefined) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (roundId: string) => {
      const { data, error } = await supabase.rpc('roll_round', { p_round_id: roundId });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [ROUND_KEY, tableId] });
      void queryClient.invalidateQueries({ queryKey: ['round-history', tableId] });
      void queryClient.invalidateQueries({ queryKey: ['wallet', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['ledger', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['tables'] });
    },
  });
}

/** Fija la apuesta en una mesa de blackjack (pendiente hasta la ronda). */
export function useSetBet(tableId: string | undefined) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (amount: number) => {
      const { data, error } = await supabase.rpc('set_bet', {
        p_table_id: tableId ?? '',
        p_amount: amount,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['table-players', tableId] });
    },
  });
}

/** Acción de blackjack: 'hit' (pide carta) o 'stand' (planta). */
export function useBlackjackAction(tableId: string | undefined) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      roundId: string;
      action: 'hit' | 'stand' | 'double' | 'insurance' | 'split';
      hand?: number;
    }) => {
      const { data, error } = await supabase.rpc('bj_action', {
        p_round_id: input.roundId,
        p_action: input.action,
        p_hand: input.hand ?? 1,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [ROUND_KEY, tableId] });
      void queryClient.invalidateQueries({ queryKey: ['round-history', tableId] });
      void queryClient.invalidateQueries({ queryKey: ['wallet', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['ledger', user?.id] });
      void queryClient.invalidateQueries({ queryKey: ['tables'] });
    },
  });
}

/** Cancela una ronda atascada y reembolsa todos. */
export function useCancelRound(tableId: string | undefined) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (roundId: string) => {
      const { data, error } = await supabase.rpc('cancel_round', { p_round_id: roundId });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [ROUND_KEY, tableId] });
      void queryClient.invalidateQueries({ queryKey: ['round-history', tableId] });
      void queryClient.invalidateQueries({ queryKey: ['tables'] });
    },
  });
}
