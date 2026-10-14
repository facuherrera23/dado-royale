import { useEffect } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';
import type { Tables } from '@/types/database.types';

export type Table = Tables<'tables'>;
export type TableWithSeated = Table & { seated: number };
export type TablePlayer = Tables<'table_players'>;
export type TablePlayerWithProfile = TablePlayer & {
  profiles: { id: string; username: string; avatar_url: string | null } | null;
};

const TABLES_KEY = 'tables';
const PLAYERS_KEY = 'table-players';

/** Lista de mesas con sus jugadores sentados, en tiempo real. */
export function useTables() {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: [TABLES_KEY],
    queryFn: async () => {
      const [{ data: tables, error: e1 }, { data: players, error: e2 }] = await Promise.all([
        supabase.from('tables').select('*').order('bet_amount'),
        supabase.from('table_players').select('*').eq('status', 'seated'),
      ]);
      if (e1) throw e1;
      if (e2) throw e2;
      const seatedByTable = new Map<string, number>();
      for (const p of players) {
        seatedByTable.set(p.table_id, (seatedByTable.get(p.table_id) ?? 0) + 1);
      }
      return tables.map((t) => ({ ...t, seated: seatedByTable.get(t.id) ?? 0 }));
    },
  });

  useEffect(() => {
    const channel = supabase
      .channel('lobby')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tables' }, () => {
        void queryClient.invalidateQueries({ queryKey: [TABLES_KEY] });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'table_players' }, () => {
        void queryClient.invalidateQueries({ queryKey: [TABLES_KEY] });
        void queryClient.invalidateQueries({ queryKey: ['my-seat'] });
      })
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return query;
}

/** Jugadores sentados en una mesa concreta (con username), en tiempo real. */
export function useTablePlayers(tableId: string | undefined) {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: [PLAYERS_KEY, tableId],
    enabled: !!tableId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('table_players')
        .select('*, profiles(id, username, avatar_url)')
        .eq('table_id', tableId ?? '')
        .eq('status', 'seated')
        .order('joined_at');
      if (error) throw error;
      return data;
    },
  });

  useEffect(() => {
    if (!tableId) return;
    const channel = supabase
      .channel(`table-players-${tableId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'table_players', filter: `table_id=eq.${tableId}` },
        () => {
          void queryClient.invalidateQueries({ queryKey: [PLAYERS_KEY, tableId] });
          void queryClient.invalidateQueries({ queryKey: [TABLES_KEY] });
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [tableId, queryClient]);

  return query;
}

/** Unirse a una mesa (el servidor valida saldo, aforo, rate limit…). */
export function useJoinTable() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (tableId: string) => {
      const { data, error } = await supabase.rpc('join_table', { p_table_id: tableId });
      if (error) throw error;
      return data;
    },
    onSuccess: (_d, tableId) => {
      void queryClient.invalidateQueries({ queryKey: [TABLES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PLAYERS_KEY, tableId] });
    },
  });
}

/** Salir de una mesa. */
export function useLeaveTable() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (tableId: string) => {
      const { data, error } = await supabase.rpc('leave_table', { p_table_id: tableId });
      if (error) throw error;
      return data;
    },
    onSuccess: (_d, tableId) => {
      void queryClient.invalidateQueries({ queryKey: [TABLES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PLAYERS_KEY, tableId] });
    },
  });
}

/** ¿En qué mesa está sentado el usuario actual (si alguna)? */
export function useMySeat() {
  const { user } = useAuth();

  // El refresco en vivo lo hace el canal 'lobby' (useTables) que invalida
  // tanto la lista de mesas como ['my-seat', user.id] en un único canal.
  return useQuery({
    queryKey: ['my-seat', user?.id],
    enabled: !!user,
    queryFn: async () => {
      if (!user) throw new Error('sin usuario');
      const { data, error } = await supabase
        .from('table_players')
        .select('table_id')
        .eq('user_id', user.id)
        .eq('status', 'seated')
        .maybeSingle();
      if (error) throw error;
      return data?.table_id ?? null;
    },
  });
}
