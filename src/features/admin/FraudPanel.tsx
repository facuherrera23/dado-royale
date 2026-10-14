import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabaseClient';

/** Panel antifraude para admins: documentos repetidos, parejas sospechosas, farming. */
export function FraudPanel() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['fraud-patterns'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_detect_patterns');
      if (error) throw error;
      return data as {
        mismo_documento: { doc_hash: string; usuarios: string[] }[];
        parejas_sospechosas: { a: string; b: string; juntas: number; wins_a: number }[];
        sin_jugar_con_faucet: { username: string; reclamos: number }[];
      };
    },
  });

  return (
    <section className="rounded-xl border border-casino-red/40 bg-casino-surface p-6">
      <h2 className="text-lg font-semibold">🕵️ Detección antifraude</h2>
      {isLoading && <p className="mt-4 animate-pulse text-casino-muted">Analizando…</p>}
      {isError && (
        <p role="alert" className="mt-4 text-casino-red">
          No se pudo cargar el análisis.
        </p>
      )}
      {data && (
        <div className="mt-4 grid gap-4 lg:grid-cols-3">
          <div className="rounded-lg border border-casino-border bg-casino-bg p-4">
            <h3 className="font-semibold text-casino-red">Documentos repetidos</h3>
            {data.mismo_documento.length === 0 && (
              <p className="mt-2 text-sm text-casino-muted">Ninguno ✓</p>
            )}
            <ul className="mt-2 space-y-1 text-sm">
              {data.mismo_documento.map((d) => (
                <li key={d.doc_hash}>
                  Mismo documento: <strong>{d.usuarios.join(', ')}</strong>
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-lg border border-casino-border bg-casino-bg p-4">
            <h3 className="font-semibold text-casino-red">Parejas con resultados dispares</h3>
            <p className="mt-1 text-xs text-casino-muted">
              ≥5 rondas juntos y uno gana ≤20% u ≥80% de las veces.
            </p>
            {data.parejas_sospechosas.length === 0 && (
              <p className="mt-2 text-sm text-casino-muted">Ninguna ✓</p>
            )}
            <ul className="mt-2 space-y-1 text-sm">
              {data.parejas_sospechosas.map((p) => (
                <li key={`${p.a}-${p.b}`}>
                  {p.a.slice(0, 8)}… vs {p.b.slice(0, 8)}… · {p.juntas} rondas, A gana {p.wins_a}
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-lg border border-casino-border bg-casino-bg p-4">
            <h3 className="font-semibold text-casino-red">Faucet sin jugar</h3>
            <p className="mt-1 text-xs text-casino-muted">
              ≥3 reclamos de fichas gratis sin jugar ni una ronda.
            </p>
            {data.sin_jugar_con_faucet.length === 0 && (
              <p className="mt-2 text-sm text-casino-muted">Ninguno ✓</p>
            )}
            <ul className="mt-2 space-y-1 text-sm">
              {data.sin_jugar_con_faucet.map((f) => (
                <li key={f.username}>
                  {f.username} — {f.reclamos} reclamos
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </section>
  );
}
