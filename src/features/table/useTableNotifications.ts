import { useEffect } from 'react';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';
import type { Tables } from '@/types/database.types';
import { toast } from '@/lib/toastStore';

export type Tournament = Tables<'tournaments'>;

/**
 * Presencia en la mesa (espectadores) + aviso cuando alguien se sienta.
 */
export function useTablePresence(tableId: string | undefined) {
  const { user, profile } = useAuth();

  useEffect(() => {
    if (!tableId || !user) return;
    const channel = supabase.channel(`presence-table-${tableId}`, {
      config: { presence: { key: user.id } },
    });
    channel
      .on('presence', { event: 'sync' }, () => {
        // Solo contamos: el estado se lee con channel.presenceState()
      })
      .subscribe((status: string) => {
        if (status === 'SUBSCRIBED') {
          void channel.track({ username: profile?.username ?? 'jugador' });
        }
      });
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [tableId, user, profile?.username]);

  return null;
}

/** Aviso en la mesa cuando alguien se sienta o se levanta (excepto yo). */
export function useSeatNotifications(tableId: string | undefined) {
  const { user } = useAuth();

  useEffect(() => {
    if (!tableId || !user) return;
    const channel = supabase
      .channel(`seats-toast-${tableId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'table_players' },
        (payload) => {
          const row = payload.new as { user_id: string; table_id: string; status: string };
          if (row.table_id === tableId && row.user_id !== user.id && row.status === 'seated') {
            toast('info', '👋 Un jugador se ha sentado en la mesa');
          }
        },
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'table_players' },
        (payload) => {
          const row = payload.new as { user_id: string; table_id: string; status: string };
          if (row.table_id === tableId && row.user_id !== user.id && row.status === 'left') {
            toast('info', '👋 Un jugador ha abandonado la mesa');
          }
        },
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'rounds', filter: `table_id=eq.${tableId}` },
        () => {
          toast('success', '🎲 ¡Ronda iniciada!');
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [tableId, user]);
}
