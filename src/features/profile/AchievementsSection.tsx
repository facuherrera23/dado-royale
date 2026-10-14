import { useEffect } from 'react';

import { useQuery, useQueryClient } from '@tanstack/react-query';

import { supabase } from '@/lib/supabaseClient';

/** Badges de logros del perfil (chequeo automático al entrar). */
export function AchievementsSection() {
  const queryClient = useQueryClient();

  useEffect(() => {
    // Idempotente: el servidor solo inserta faltantes
    void supabase.rpc('check_achievements').then(({ error }) => {
      if (!error) void queryClient.invalidateQueries({ queryKey: ['achievements'] });
    });
  }, [queryClient]);

  const { data } = useQuery({
    queryKey: ['achievements'],
    queryFn: async () => {
      const { data: all, error: e1 } = await supabase.from('achievements').select('*');
      const { data: mine, error: e2 } = await supabase.from('user_achievements').select('*');
      if (e1) throw e1;
      if (e2) throw e2;
      return { all, earned: new Set(mine.map((m) => m.achievement_key)) };
    },
  });

  if (!data) return null;

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">🏅 Logros</h2>
      <p className="mt-1 text-sm text-casino-muted">
        {data.earned.size} de {data.all.length} desbloqueados
      </p>
      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
        {data.all.map((a) => {
          const earned = data.earned.has(a.key);
          return (
            <div
              key={a.key}
              className={`rounded-lg border p-3 text-center ${
                earned
                  ? 'border-casino-gold bg-casino-gold/10'
                  : 'border-casino-border bg-casino-bg opacity-60'
              }`}
              title={a.description}
            >
              <p className="text-2xl">{a.icon}</p>
              <p className="mt-1 text-xs font-semibold">{a.name}</p>
              <p className="mt-0.5 text-[11px] text-casino-muted">{a.description}</p>
            </div>
          );
        })}
      </div>
    </section>
  );
}
