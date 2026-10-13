import type { Session, User } from '@supabase/supabase-js';
import { create } from 'zustand';

import type { Tables } from '@/types/database.types';

export type Profile = Tables<'profiles'>;

interface AuthState {
  /** null = aún cargando la sesión inicial */
  session: Session | null | undefined;
  user: User | null;
  profile: Profile | null;
  setSession: (session: Session | null) => void;
  setProfile: (profile: Profile | null) => void;
}

/** Estado global de autenticación. La sesión persiste en localStorage (Supabase). */
export const useAuthStore = create<AuthState>((set) => ({
  session: undefined,
  user: null,
  profile: null,
  setSession: (session) => {
    set({ session, user: session?.user ?? null });
  },
  setProfile: (profile) => {
    set({ profile });
  },
}));
