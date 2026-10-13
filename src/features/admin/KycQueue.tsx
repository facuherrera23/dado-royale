import { useState } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { useAuth } from '@/features/auth/useAuth';
import { supabase } from '@/lib/supabaseClient';

/** Cola de revisión KYC para administradores. */
export function KycQueue() {
  const { profile } = useAuth();
  const queryClient = useQueryClient();
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [docUrls, setDocUrls] = useState<Record<string, string>>({});

  const { data: submissions, isLoading } = useQuery({
    queryKey: ['kyc-queue'],
    enabled: profile?.is_admin === true,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('kyc_submissions')
        .select('*, profiles!kyc_submissions_user_id_fkey(username, avatar_url)')
        .eq('status', 'pending')
        .order('created_at');
      if (error) throw error;
      return data;
    },
  });

  const review = useMutation({
    mutationFn: async (input: { id: string; approve: boolean; reason?: string }) => {
      const { data, error } = await supabase.rpc('review_kyc', {
        p_submission: input.id,
        p_approve: input.approve,
        p_reason: input.reason ?? undefined,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['kyc-queue'] });
      void queryClient.invalidateQueries({ queryKey: ['admin-stats'] });
    },
  });

  const viewDoc = async (path: string, key: string) => {
    const { data, error } = await supabase.storage.from('kyc-documents').createSignedUrl(path, 300);
    if (!error) {
      setDocUrls((m) => ({ ...m, [key]: data.signedUrl }));
    }
  };

  if (!profile?.is_admin) return null;

  return (
    <section className="rounded-xl border border-casino-border bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">🛂 Solicitudes KYC pendientes</h2>
      {isLoading && <p className="mt-4 animate-pulse text-casino-muted">Cargando…</p>}
      {submissions && submissions.length === 0 && (
        <p className="mt-4 text-sm text-casino-muted">No hay solicitudes pendientes. 🎉</p>
      )}
      <ul className="mt-4 flex flex-col gap-4">
        {submissions?.map((s) => (
          <li key={s.id} className="rounded-lg border border-casino-border bg-casino-bg p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-medium">
                {s.full_name} <span className="text-casino-muted">({s.profiles.username})</span>
              </p>
              <p className="text-sm text-casino-muted">
                {new Date(s.created_at).toLocaleString('es')} · {s.doc_type} · {s.country}
              </p>
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {(['front', 'back'] as const).map((side) => {
                const path = side === 'front' ? s.doc_path_front : s.doc_path_back;
                if (!path) return null;
                const key = `${s.id}:${side}`;
                return docUrls[key] ? (
                  <a
                    key={side}
                    href={docUrls[key]}
                    target="_blank"
                    rel="noreferrer"
                    className="text-sm text-casino-gold underline"
                  >
                    Ver {side === 'front' ? 'frente' : 'reverso'} (5 min)
                  </a>
                ) : (
                  <button
                    key={side}
                    onClick={() => void viewDoc(path, key)}
                    className="rounded-md border border-casino-border px-3 py-1 text-sm text-casino-muted hover:text-casino-text"
                  >
                    Obtener enlace seguro ({side === 'front' ? 'frente' : 'reverso'})
                  </button>
                );
              })}
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <button
                onClick={() => {
                  review.mutate({ id: s.id, approve: true });
                }}
                disabled={review.isPending}
                className="rounded-md bg-casino-green px-4 py-2 text-sm font-semibold text-white enabled:hover:opacity-90 disabled:opacity-40"
              >
                ✅ Aprobar
              </button>
              <input
                placeholder="Motivo del rechazo…"
                value={reasons[s.id] ?? ''}
                onChange={(e) => {
                  setReasons((r) => ({ ...r, [s.id]: e.target.value }));
                }}
                className="min-w-48 flex-1 rounded-md border border-casino-border bg-casino-surface px-3 py-1.5 text-sm text-casino-text"
              />
              <button
                onClick={() => {
                  review.mutate({ id: s.id, approve: false, reason: reasons[s.id] ?? '' });
                }}
                disabled={review.isPending || (reasons[s.id] ?? '').trim().length < 4}
                className="rounded-md bg-casino-red px-4 py-2 text-sm font-semibold text-white enabled:hover:opacity-90 disabled:opacity-40"
              >
                ❌ Rechazar
              </button>
            </div>
            {review.isError && (
              <p role="alert" className="mt-2 text-sm text-casino-red">
                {review.error.message}
              </p>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}
