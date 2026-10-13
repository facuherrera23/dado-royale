import { lazy, Suspense } from 'react';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { HashRouter, Navigate, Route, Routes } from 'react-router-dom';

import { AuthPage } from '@/features/auth/AuthPage';
import { RedirectIfAuthed, RequireAuth } from '@/features/auth/guards';
import { useAuthSync } from '@/features/auth/useAuth';
import { LobbyPage } from '@/features/lobby/LobbyPage';

import { AppShell } from './AppShell';

// Code-splitting por ruta: cada pantalla viaja en su propio chunk.
const TablePage = lazy(async () => ({
  default: (await import('@/features/table/TablePage')).TablePage,
}));
const WalletPage = lazy(async () => ({
  default: (await import('@/features/wallet/WalletPage')).WalletPage,
}));
const RankingPage = lazy(async () => ({
  default: (await import('@/features/ranking/RankingPage')).RankingPage,
}));
const AdminPage = lazy(async () => ({
  default: (await import('@/features/admin/AdminPage')).AdminPage,
}));
const TermsPage = lazy(async () => ({
  default: (await import('@/features/legal/TermsPage')).TermsPage,
}));
const ProfilePage = lazy(async () => ({
  default: (await import('@/features/profile/ProfilePage')).ProfilePage,
}));

function PageFallback() {
  return (
    <div className="flex min-h-screen items-center justify-center" role="status">
      <span className="animate-pulse text-casino-muted">Cargando…</span>
    </div>
  );
}

// HashRouter es obligatorio: GitHub Pages no soporta rewrites de SPA.
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

export function App() {
  useAuthSync();

  return (
    <QueryClientProvider client={queryClient}>
      <HashRouter>
        <Suspense fallback={<PageFallback />}>
          <Routes>
            <Route path="/" element={<Navigate to="/lobby" replace />} />
            <Route path="/terminos" element={<TermsPage />} />
            <Route
              path="/auth"
              element={
                <RedirectIfAuthed>
                  <AuthPage />
                </RedirectIfAuthed>
              }
            />
            <Route element={<RequireAuth />}>
              <Route element={<AppShell />}>
                <Route path="/lobby" element={<LobbyPage />} />
                <Route path="/mesa/:id" element={<TablePage />} />
                <Route path="/wallet" element={<WalletPage />} />
                <Route path="/ranking" element={<RankingPage />} />
                <Route path="/perfil" element={<ProfilePage />} />
                <Route path="/admin" element={<AdminPage />} />
              </Route>
            </Route>
            <Route path="*" element={<Navigate to="/lobby" replace />} />
          </Routes>
        </Suspense>
      </HashRouter>
    </QueryClientProvider>
  );
}
