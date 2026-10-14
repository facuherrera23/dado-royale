import { useEffect, useState } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

/** Chat de una mesa: lectura pública + Realtime; escribir solo sentados. */
export function ChatPanel({ tableId, seated }: { tableId: string; seated: boolean }) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [text, setText] = useState('');

  const { data: messages } = useQuery({
    queryKey: ['chat', tableId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('table_messages')
        .select('*, profiles(username)')
        .eq('table_id', tableId)
        .order('created_at', { ascending: true })
        .limit(100);
      if (error) throw error;
      return data;
    },
  });

  useEffect(() => {
    const channel = supabase
      .channel(`chat-${tableId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'table_messages',
          filter: `table_id=eq.${tableId}`,
        },
        () => {
          void queryClient.invalidateQueries({ queryKey: ['chat', tableId] });
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [tableId, queryClient]);

  const send = useMutation({
    mutationFn: async (body: string) => {
      const { error } = await supabase.rpc('send_table_message', {
        p_table_id: tableId,
        p_body: body,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setText('');
    },
  });

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-4">
      <h2 className="text-base font-semibold">💬 Chat de la mesa</h2>
      <div
        className="mt-3 flex h-56 flex-col gap-1.5 overflow-y-auto rounded-lg border border-casino-border bg-casino-bg p-3"
        role="log"
        aria-label="Mensajes de la mesa"
      >
        {messages && messages.length === 0 && (
          <p className="text-sm text-casino-muted">Nadie ha hablado todavía. ¡Saluda!</p>
        )}
        {messages?.map((m) => (
          <p key={m.id} className="text-sm">
            <span
              className={
                m.user_id === user?.id
                  ? 'font-semibold text-casino-gold'
                  : 'font-semibold text-casino-text'
              }
            >
              {m.profiles.username}
            </span>{' '}
            <span className="text-casino-muted">{m.body}</span>
          </p>
        ))}
      </div>

      {seated && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (text.trim()) send.mutate(text.trim());
          }}
          className="mt-3 flex gap-2"
        >
          <input
            value={text}
            onChange={(e) => {
              setText(e.target.value);
            }}
            maxLength={500}
            placeholder="Escribe algo…"
            aria-label="Escribir mensaje"
            className="flex-1 rounded-md border border-casino-border bg-casino-bg px-3 py-2 text-sm text-casino-text placeholder:text-casino-muted focus:border-casino-gold focus:outline-none"
          />
          <button
            type="submit"
            disabled={!text.trim() || send.isPending}
            className="rounded-md bg-casino-gold px-4 py-2 text-sm font-semibold text-black disabled:opacity-40"
          >
            Enviar
          </button>
        </form>
      )}
      {!seated && (
        <p className="mt-3 text-xs text-casino-muted">
          👀 Estás de espectador: siéntate para chatear.
        </p>
      )}
      {send.isError && (
        <p role="alert" className="mt-1 text-xs text-casino-red">
          {send.error.message}
        </p>
      )}
    </section>
  );
}
