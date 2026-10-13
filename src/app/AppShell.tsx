import { Link, NavLink, Outlet } from 'react-router-dom';

import { Avatar } from '@/components/Avatar';
import { useAuth } from '@/features/auth/useAuth';
import { BalanceBadge } from '@/features/wallet/Balance';
import { syncAmbient } from '@/lib/sounds';
import { useUiStore } from '@/lib/uiStore';

const linkClass = ({ isActive }: { isActive: boolean }) =>
  `rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
    isActive ? 'bg-casino-gold text-black' : 'text-casino-muted hover:text-casino-text'
  }`;

/** Estructura común de las páginas autenticadas: cabecera con navegación. */
export function AppShell() {
  const { profile, signOut } = useAuth();
  const isAdmin = profile?.is_admin ?? false;
  const { muted, ambient, toggleMuted, toggleAmbient } = useUiStore();

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-casino-border bg-casino-surface">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3">
          <span className="text-lg font-bold text-casino-gold">🎲 Dado Royale</span>
          <nav className="flex items-center gap-2" aria-label="principal">
            <NavLink to="/lobby" className={linkClass}>
              Lobby
            </NavLink>
            <NavLink to="/wallet" className={linkClass}>
              Billetera
            </NavLink>
            <NavLink to="/ranking" className={linkClass}>
              Ranking
            </NavLink>
            {isAdmin && (
              <NavLink to="/admin" className={linkClass}>
                Admin
              </NavLink>
            )}
          </nav>
          <div className="flex items-center gap-3">
            <BalanceBadge />
            <button
              onClick={() => {
                toggleAmbient();
                syncAmbient();
              }}
              aria-label={ambient ? 'Quitar sonido ambiente' : 'Activar sonido ambiente de casino'}
              aria-pressed={ambient}
              className="rounded-md border border-casino-border px-2.5 py-1.5 text-sm text-casino-muted transition-colors hover:text-casino-text"
            >
              🎰
            </button>
            <button
              onClick={() => {
                toggleMuted();
                syncAmbient();
              }}
              aria-label={muted ? 'Activar sonido' : 'Silenciar sonido'}
              aria-pressed={muted}
              className="rounded-md border border-casino-border px-2.5 py-1.5 text-sm text-casino-muted transition-colors hover:text-casino-text"
            >
              {muted ? '🔇' : '🔊'}
            </button>
            <Link
              to="/perfil"
              className="flex items-center gap-2 rounded-md px-1 py-0.5 text-sm text-casino-muted transition-colors hover:text-casino-text"
              title="Mi perfil"
            >
              {profile && (
                <Avatar username={profile.username} avatarUrl={profile.avatar_url} size="sm" />
              )}
              {profile?.username ?? '…'}
            </Link>
            <button
              onClick={() => void signOut()}
              className="rounded-md border border-casino-border px-3 py-1.5 text-sm text-casino-muted transition-colors hover:border-casino-red hover:text-casino-red"
            >
              Salir
            </button>
          </div>
        </div>
      </header>
      <div className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">
        <Outlet />
      </div>
      <footer className="border-t border-casino-border py-4 text-center text-xs text-casino-muted">
        Las fichas son virtuales y sin valor monetario · Solo mayores de 18 años ·{' '}
        <Link to="/terminos" className="underline hover:text-casino-text">
          Términos y juego responsable
        </Link>
      </footer>
    </div>
  );
}
