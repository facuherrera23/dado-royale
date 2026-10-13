import { useRef, useState } from 'react';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
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
  docType: z.enum(['dni', 'passport', 'license'], { error: 'Elige el tipo de documento' }),
  docId: z.string().min(6, 'Mínimo 6 caracteres'),
});

type KycInput = z.infer<typeof kycSchema>;

const DOC_LABELS: Record<string, string> = {
  dni: 'DNI / Cédula',
  passport: 'Pasaporte',
  license: 'Licencia de conducir',
};

/**
 * KYC real: sube la foto del documento (Storage privado, solo tu carpeta)
 * y envía la solicitud a revisión humana. El perfil solo se verifica tras
 * aprobación de un administrador.
 */
export function KycPage() {
  const { user, profile } = useAuth();
  const setProfile = useAuthStore((s) => s.setProfile);
  const queryClient = useQueryClient();

  const [form, setForm] = useState({
    fullName: '',
    dob: '',
    country: '',
    docType: 'dni' as KycInput['docType'],
    docId: '',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const frontRef = useRef<HTMLInputElement>(null);
  const backRef = useRef<HTMLInputElement>(null);

  // Estado de mi última solicitud
  const { data: mySubmission } = useQuery({
    queryKey: ['my-kyc', user?.id],
    enabled: !!user,
    queryFn: async () => {
      if (!user) throw new Error('sin usuario');
      const { data, error } = await supabase
        .from('kyc_submissions')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const submit = useMutation({
    mutationFn: async (input: KycInput & { frontPath: string; backPath: string | null }) => {
      const { data, error } = await supabase.rpc('submit_kyc', {
        p_full_name: input.fullName,
        p_dob: input.dob,
        p_country: input.country.toUpperCase(),
        p_doc_type: input.docType,
        p_doc_id: input.docId,
        p_doc_path_front: input.frontPath,
        p_doc_path_back: input.backPath ?? undefined,
      });
      if (error) throw error;
      return data as { kyc_status: string };
    },
    onSuccess: async () => {
      void queryClient.invalidateQueries({ queryKey: ['my-kyc', user?.id] });
      if (profile) {
        const { data } = await supabase.from('profiles').select('*').eq('id', profile.id).single();
        if (data) setProfile(data);
      }
    },
  });

  if (profile?.kyc_verified) {
    return <Navigate to="/lobby" replace />;
  }

  const uploadFile = async (input: HTMLInputElement | null, kind: 'front' | 'back') => {
    const file = input?.files?.[0];
    if (!file || !user) return null;
    if (file.size > 5 * 1024 * 1024) throw new Error('El archivo supera los 5 MB');
    const ext = file.name.split('.').pop() ?? 'jpg';
    const path = `${user.id}/${kind}.${ext}`;
    const { error } = await supabase.storage
      .from('kyc-documents')
      .upload(path, file, { upsert: true });
    if (error) throw error;
    return path;
  };

  const handleSubmit = async (e: React.SyntheticEvent) => {
    e.preventDefault();
    setErrors({});
    const parsed = kycSchema.safeParse(form);
    if (!parsed.success) {
      const out: Record<string, string> = {};
      for (const issue of parsed.error.issues) out[String(issue.path[0])] = issue.message;
      setErrors(out);
      return;
    }
    if (!frontRef.current?.files?.[0]) {
      setErrors({ front: 'Sube la foto del frente del documento' });
      return;
    }
    try {
      const frontPath = await uploadFile(frontRef.current, 'front');
      const backPath = await uploadFile(backRef.current, 'back');
      if (frontPath) {
        submit.mutate({ ...parsed.data, frontPath, backPath });
      }
    } catch (err) {
      setErrors({ front: err instanceof Error ? err.message : 'Error al subir el archivo' });
    }
  };

  const inputClass =
    'w-full rounded-md border border-casino-border bg-casino-bg px-3 py-2 text-casino-text placeholder:text-casino-muted focus:border-casino-gold focus:outline-none focus:ring-1 focus:ring-casino-gold';

  return (
    <main className="mx-auto max-w-md py-8">
      <div className="rounded-xl border border-casino-border bg-casino-surface p-6">
        <h1 className="text-2xl font-bold text-casino-gold">Verificación de identidad (18+)</h1>
        <p className="mt-2 text-sm text-casino-muted">
          Sube tu documento y envíalo a revisión. Un administrador lo verificará. Tu número de
          documento se guarda solo como hash criptográfico.
        </p>

        {mySubmission && mySubmission.status !== 'approved' && (
          <div
            role="status"
            className={`mt-4 rounded-lg border p-4 text-sm ${
              mySubmission.status === 'pending'
                ? 'border-casino-gold/50 bg-casino-gold/10 text-casino-gold'
                : 'border-casino-red/50 bg-casino-red/10 text-casino-red'
            }`}
          >
            <p className="font-semibold">
              {mySubmission.status === 'pending'
                ? '⏳ Tu solicitud está en revisión'
                : `❌ Rechazada: ${mySubmission.rejection_reason ?? 'sin motivo'}`}
            </p>
            {mySubmission.status === 'rejected' && (
              <p className="mt-1">Puedes corregir los datos y volver a enviarla.</p>
            )}
          </div>
        )}

        {(!mySubmission || mySubmission.status === 'rejected') && (
          <form
            onSubmit={(e) => void handleSubmit(e)}
            className="mt-6 flex flex-col gap-4"
            noValidate
          >
            <div>
              <label htmlFor="fullName" className="mb-1 block text-sm text-casino-muted">
                Nombre completo
              </label>
              <input
                id="fullName"
                value={form.fullName}
                onChange={(e) => {
                  setForm((f) => ({ ...f, fullName: e.target.value }));
                }}
                className={inputClass}
                placeholder="Ana García"
              />
              {errors.fullName && (
                <p role="alert" className="mt-1 text-sm text-casino-red">
                  {errors.fullName}
                </p>
              )}
            </div>

            <div>
              <label htmlFor="dob" className="mb-1 block text-sm text-casino-muted">
                Fecha de nacimiento
              </label>
              <input
                id="dob"
                type="date"
                value={form.dob}
                onChange={(e) => {
                  setForm((f) => ({ ...f, dob: e.target.value }));
                }}
                className={inputClass}
              />
              {errors.dob && (
                <p role="alert" className="mt-1 text-sm text-casino-red">
                  {errors.dob}
                </p>
              )}
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label htmlFor="country" className="mb-1 block text-sm text-casino-muted">
                  País (ISO)
                </label>
                <input
                  id="country"
                  value={form.country}
                  onChange={(e) => {
                    setForm((f) => ({ ...f, country: e.target.value }));
                  }}
                  className={inputClass}
                  placeholder="ES"
                  maxLength={2}
                />
                {errors.country && (
                  <p role="alert" className="mt-1 text-sm text-casino-red">
                    {errors.country}
                  </p>
                )}
              </div>
              <div>
                <label htmlFor="docType" className="mb-1 block text-sm text-casino-muted">
                  Tipo de documento
                </label>
                <select
                  id="docType"
                  value={form.docType}
                  onChange={(e) => {
                    setForm((f) => ({ ...f, docType: e.target.value as KycInput['docType'] }));
                  }}
                  className={inputClass}
                >
                  {Object.entries(DOC_LABELS).map(([v, l]) => (
                    <option key={v} value={v}>
                      {l}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label htmlFor="docId" className="mb-1 block text-sm text-casino-muted">
                Nº de documento
              </label>
              <input
                id="docId"
                value={form.docId}
                onChange={(e) => {
                  setForm((f) => ({ ...f, docId: e.target.value }));
                }}
                className={inputClass}
                placeholder="12345678X"
              />
              {errors.docId && (
                <p role="alert" className="mt-1 text-sm text-casino-red">
                  {errors.docId}
                </p>
              )}
            </div>

            <div>
              <label htmlFor="front" className="mb-1 block text-sm text-casino-muted">
                Foto del frente del documento *
              </label>
              <input
                id="front"
                ref={frontRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,application/pdf"
                className="w-full text-sm text-casino-muted file:mr-3 file:rounded-md file:border-0 file:bg-casino-gold file:px-3 file:py-2 file:text-sm file:font-semibold file:text-black"
              />
              {errors.front && (
                <p role="alert" className="mt-1 text-sm text-casino-red">
                  {errors.front}
                </p>
              )}
            </div>

            <div>
              <label htmlFor="back" className="mb-1 block text-sm text-casino-muted">
                Foto del reverso (opcional)
              </label>
              <input
                id="back"
                ref={backRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,application/pdf"
                className="w-full text-sm text-casino-muted file:mr-3 file:rounded-md file:border-0 file:bg-casino-border file:px-3 file:py-2 file:text-sm file:text-casino-muted"
              />
            </div>

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
              {submit.isPending ? 'Enviando a revisión…' : 'Enviar a revisión'}
            </button>
          </form>
        )}
      </div>
    </main>
  );
}
