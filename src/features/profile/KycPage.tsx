import { useState } from 'react';

import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Navigate } from 'react-router-dom';
import { z } from 'zod';

import { useAuth } from '@/features/auth/useAuth';
import { useAuthStore } from '@/features/auth/authStore';
import { supabase } from '@/lib/supabaseClient';

const kycSchema = z.object({
  fullName: z
    .string()
    .min(5, 'Nombre y apellido (mínimo 5 caracteres)')
    .refine((v) => v.trim().includes(' '), 'Introduce nombre y apellido'),
  dob: z
    .string()
    .refine((v) => !Number.isNaN(Date.parse(v)), 'Fecha inválida')
    .refine((v) => {
      const age = (Date.now() - new Date(v).getTime()) / (365.25 * 24 * 3600 * 1000);
      return age >= 18;
    }, 'Debes ser mayor de 18 años'),
  country: z.string().regex(/^[A-Za-z]{2}$/, 'Código ISO de 2 letras (ES, AR, MX…)'),
  docId: z.string().min(6, 'Mínimo 6 caracteres'),
});

export type KycInput = z.infer<typeof kycSchema>;

/** Página de verificación de identidad (KYC ligero 18+). */
export function KycPage() {
  const { profile } = useAuth();
  const setProfile = useAuthStore((s) => s.setProfile);
  const queryClient = useQueryClient();

  const [form, setForm] = useState({ fullName: '', dob: '', country: '', docId: '' });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const submit = useMutation({
    mutationFn: async (input: KycInput) => {
      const { data, error } = await supabase.rpc('submit_kyc', {
        p_full_name: input.fullName,
        p_dob: input.dob,
        p_country: input.country.toUpperCase(),
        p_doc_id: input.docId,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: async () => {
      if (profile) {
        const { data } = await supabase.from('profiles').select('*').eq('id', profile.id).single();
        if (data) setProfile(data);
      }
      void queryClient.invalidateQueries();
    },
  });

  if (profile?.kyc_verified) {
    return <Navigate to="/lobby" replace />;
  }

  const handleSubmit = (e: React.SyntheticEvent) => {
    e.preventDefault();
    setErrors({});
    const parsed = kycSchema.safeParse(form);
    if (!parsed.success) {
      const out: Record<string, string> = {};
      for (const issue of parsed.error.issues) out[String(issue.path[0])] = issue.message;
      setErrors(out);
      return;
    }
    submit.mutate(parsed.data);
  };

  const inputClass =
    'w-full rounded-md border border-casino-border bg-casino-bg px-3 py-2 text-casino-text placeholder:text-casino-muted focus:border-casino-gold focus:outline-none focus:ring-1 focus:ring-casino-gold';

  const field = (id: keyof typeof form, label: string, type = 'text', placeholder = '') => (
    <div>
      <label htmlFor={id} className="mb-1 block text-sm text-casino-muted">
        {label}
      </label>
      <input
        id={id}
        type={type}
        placeholder={placeholder}
        value={form[id]}
        onChange={(e) => {
          setForm((f) => ({ ...f, [id]: e.target.value }));
        }}
        className={inputClass}
      />
      {errors[id] && (
        <p role="alert" className="mt-1 text-sm text-casino-red">
          {errors[id]}
        </p>
      )}
    </div>
  );

  return (
    <main className="mx-auto max-w-md py-8">
      <div className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <h1 className="text-2xl font-bold text-casino-gold">Verificación de identidad (18+)</h1>
        <p className="mt-2 text-sm text-casino-muted">
          Para jugar debes confirmar tu identidad y mayoría de edad. Tu documento se guarda solo
          como hash criptográfico (nunca en claro). Sin KYC no podrás sentarte en mesas.
        </p>

        <form onSubmit={handleSubmit} className="mt-6 flex flex-col gap-4" noValidate>
          {field('fullName', 'Nombre completo', 'text', 'Ana García')}
          {field('dob', 'Fecha de nacimiento', 'date')}
          {field('country', 'País (ISO)', 'text', 'ES')}
          {field('docId', 'Documento de identidad', 'text', 'DNI / Cédula / Pasaporte')}

          {submit.isError && (
            <p
              role="alert"
              className="rounded-md border border-casino-red/50 bg-casino-red/10 p-3 text-sm text-casino-red"
            >
              {submit.error.message}
            </p>
          )}

          <button
            type="submit"
            disabled={submit.isPending}
            className="rounded-md bg-casino-gold px-4 py-2 font-semibold text-black transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {submit.isPending ? 'Verificando…' : 'Verificar identidad'}
          </button>
        </form>
      </div>
    </main>
  );
}
