import { z } from 'zod';

/**
 * Variables de entorno públicas del frontend.
 *
 * SOLO se permiten claves anon/públicas. La service_role key JAMÁS debe
 * aparecer en una variable VITE_* (todo lo VITE_* se embebe en el bundle
 * del navegador y es visible para cualquiera).
 */
const envSchema = z.object({
  VITE_SUPABASE_URL: z.url(),
  VITE_SUPABASE_ANON_KEY: z.string().min(1, 'Falta la anon key de Supabase'),
});

function loadEnv() {
  const metaEnv = import.meta.env as Record<string, unknown>;
  const parsed = envSchema.safeParse({
    VITE_SUPABASE_URL: metaEnv.VITE_SUPABASE_URL,
    VITE_SUPABASE_ANON_KEY: metaEnv.VITE_SUPABASE_ANON_KEY,
  });

  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(
      `Configuración de entorno inválida (${issues}). Copia .env.example a .env y completa los valores.`,
    );
  }

  return parsed.data;
}

export const env = loadEnv();
