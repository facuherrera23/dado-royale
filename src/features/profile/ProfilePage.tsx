import { useMutation, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';
import { useState } from 'react';

import { Avatar } from '@/components/Avatar';
import { AVATARS } from '@/lib/avatars';

/** Perfil: avatar editable (emoji), nombre y estadísticas rápidas. */
export function ProfilePage() {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [picked, setPicked] = useState<string | null>(profile?.avatar_url ?? null);
  const save = useMutation({
    mutationFn: async (emoji: string | null) => {
      const { error } = await supabase
        .from('profiles')
        .update({ avatar_url: emoji })
        .eq('id', user?.id ?? '');
      if (error) throw error;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries();
    },
  });
  const avatar = picked ?? null;

  if (!profile) {
    return <p className="animate-pulse text-casino-muted">Cargando perfil…</p>;
  }

  return (
    <main className="flex max-w-lg flex-col gap-6">
      <h1 className="text-2xl font-bold">Mi perfil</h1>

      <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <div className="flex items-center gap-4">
          <Avatar username={profile.username} avatarUrl={avatar} size="lg" />
          <div>
            <p className="text-lg font-semibold">{profile.username}</p>
            <p className="text-sm text-casino-muted">{user?.email}</p>
            <p className="mt-1 text-xs text-casino-muted">
              Miembro desde {new Date(profile.created_at).toLocaleDateString('es')}
            </p>
          </div>
        </div>
      </section>

      <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <h2 className="text-lg font-semibold">Elige tu avatar</h2>
        <div className="mt-4 grid grid-cols-4 gap-2 sm:grid-cols-8">
          {AVATARS.map((emoji) => (
            <button
              key={emoji}
              onClick={() => {
                setPicked(emoji);
                save.mutate(emoji);
              }}
              aria-label={`Avatar ${emoji}`}
              aria-pressed={avatar === emoji}
              className={`rounded-lg border-2 p-3 text-2xl transition-transform enabled:hover:scale-110 ${
                avatar === emoji
                  ? 'border-casino-gold bg-casino-gold/10'
                  : 'border-casino-border bg-casino-bg'
              }`}
            >
              {emoji}
            </button>
          ))}
        </div>
        {save.isPending && <p className="mt-3 text-sm text-casino-muted">Guardando…</p>}
        {save.isSuccess && (
          <p role="status" className="mt-3 text-sm text-casino-green">
            ¡Avatar actualizado!
          </p>
        )}
        {save.isError && (
          <p role="alert" className="mt-3 text-sm text-casino-red">
            {save.error.message}
          </p>
        )}
      </section>
    </main>
  );
}
