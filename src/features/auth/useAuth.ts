import { useEffect } from 'react';

import { supabase } from '@/lib/supabaseClient';

import { useAuthStore } from './authStore';

async function loadProfile(userId: string) {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).single();
  if (error) {
    // Puede haber una carrera mínima con el trigger de alta; no bloqueamos la app.
    console.error('No se pudo cargar el perfil:', error.message);
    return null;
  }
  return data;
}

/**
 * Sincroniza el store con la sesión de Supabase.
 * Debe montarse una sola vez, en la raíz de la app.
 */
export function useAuthSync() {
  const setSession = useAuthStore((s) => s.setSession);
  const setProfile = useAuthStore((s) => s.setProfile);

  useEffect(() => {
    supabase.auth
      .getSession()
      .then(async ({ data: { session } }) => {
        setSession(session);
        setProfile(session ? await loadProfile(session.user.id) : null);
      })
      .catch((err: unknown) => {
        console.error('Error obteniendo sesión:', err);
        setSession(null);
      });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      setSession(session);
      if (event === 'SIGNED_IN' && session) {
        void loadProfile(session.user.id).then(setProfile);
      }
      if (event === 'SIGNED_OUT') {
        setProfile(null);
      }
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [setSession, setProfile]);
}

export function useAuth() {
  const { session, user, profile } = useAuthStore();
  return {
    session,
    user,
    profile,
    isLoading: session === undefined,
    isAuthenticated: !!session,
    signOut: () => supabase.auth.signOut(),
  };
}
