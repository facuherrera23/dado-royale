import { Navigate, Outlet } from 'react-router-dom';

import { useAuth } from './useAuth';

/** Rutas que solo ven usuarios autenticados. */
export function RequireAuth() {
  const { isLoading, isAuthenticated } = useAuth();

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center" role="status">
        <span className="animate-pulse text-casino-muted">Cargando…</span>
      </div>
    );
  }
  if (!isAuthenticated) {
    return <Navigate to="/auth" replace />;
  }
  return <Outlet />;
}

/** Detrás del login: exige KYC verificado para jugar (el servidor también lo fuerza). */
export function RequireKyc() {
  const { profile } = useAuth();
  if (profile && !profile.kyc_verified) {
    return <Navigate to="/verificacion" replace />;
  }
  return <Outlet />;
}

/** Rutas públicas que redirigen al lobby si ya hay sesión. */
export function RedirectIfAuthed({ children }: { children: React.ReactNode }) {
  const { isLoading, isAuthenticated } = useAuth();
  if (isLoading) return null;
  if (isAuthenticated) return <Navigate to="/lobby" replace />;
  return <>{children}</>;
}
