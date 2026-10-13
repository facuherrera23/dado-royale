import { createClient } from '@supabase/supabase-js';

import type { Database } from '@/types/database.types';

import { env } from './env';

/**
 * Cliente Supabase único para toda la app, tipado con el esquema generado.
 * Usa únicamente la anon key: toda escritura sensible pasa por funciones
 * RPC SECURITY DEFINER en el servidor.
 */
export const supabase = createClient<Database>(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
