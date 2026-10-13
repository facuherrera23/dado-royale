import { useState } from 'react';

import { supabase } from '@/lib/supabaseClient';

import { loginSchema, registerSchema, type LoginInput, type RegisterInput } from './schemas';

type Mode = 'login' | 'register';

function FieldError({ message }: { message?: string }) {
  if (!message) return null;
  return (
    <p role="alert" className="mt-1 text-sm text-casino-red">
      {message}
    </p>
  );
}

const inputClass =
  'w-full rounded-md border border-casino-border bg-casino-bg px-3 py-2 text-casino-text placeholder:text-casino-muted focus:border-casino-gold focus:outline-none focus:ring-1 focus:ring-casino-gold';

/**
 * Pantalla de autenticación: login o registro con email/contraseña.
 * Validación con Zod en cliente; el servidor vuelve a validar todo.
 */
export function AuthPage() {
  const [mode, setMode] = useState<Mode>('login');
  const [form, setForm] = useState({
    username: '',
    email: '',
    password: '',
    confirmPassword: '',
    acceptAdult: false,
    acceptTerms: false,
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [serverError, setServerError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const set = (key: string, value: string | boolean) => {
    setForm((f) => ({ ...f, [key]: value }));
    setErrors((e) => Object.fromEntries(Object.entries(e).filter(([k]) => k !== key)));
  };

  const zodFieldErrors = (issues: { path: PropertyKey[]; message: string }[]) => {
    const out: Record<string, string> = {};
    for (const issue of issues) {
      const field = String(issue.path[0] ?? '');
      if (!(field in out)) out[field] = issue.message;
    }
    return out;
  };

  const handleSubmit = async (e: React.SyntheticEvent) => {
    e.preventDefault();
    setServerError(null);
    setInfo(null);
    setErrors({});

    if (mode === 'login') {
      const input: LoginInput = { email: form.email, password: form.password };
      const parsed = loginSchema.safeParse(input);
      if (!parsed.success) {
        setErrors(zodFieldErrors(parsed.error.issues));
        return;
      }
      setLoading(true);
      const { error } = await supabase.auth.signInWithPassword(parsed.data);
      setLoading(false);
      if (error) {
        setServerError(
          error.message === 'Invalid login credentials'
            ? 'Email o contraseña incorrectos.'
            : error.message,
        );
      }
      // Si hay éxito, RedirectIfAuthed/navegación se encargan vía onAuthStateChange.
      return;
    }

    const input: RegisterInput = {
      username: form.username,
      email: form.email,
      password: form.password,
      confirmPassword: form.confirmPassword,
      acceptAdult: form.acceptAdult as true,
      acceptTerms: form.acceptTerms as true,
    };
    const parsed = registerSchema.safeParse(input);
    if (!parsed.success) {
      setErrors(zodFieldErrors(parsed.error.issues));
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        data: {
          username: parsed.data.username,
          adult_confirmed: true,
          terms_accepted_at: new Date().toISOString(),
        },
      },
    });
    setLoading(false);
    if (error) {
      if (error.message.toLowerCase().includes('username')) {
        setErrors({ username: 'Ese nombre de usuario ya está en uso.' });
      } else {
        setServerError(error.message);
      }
      return;
    }
    if (!data.session) {
      setInfo('¡Cuenta creada! Revisa tu email para verificar la cuenta e iniciar sesión.');
    }
  };

  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-10">
      <div className="w-full max-w-md rounded-xl border border-casino-border bg-casino-surface p-6 shadow-xl">
        <h1 className="text-center text-2xl font-bold text-casino-gold">🎲 Dado Royale</h1>

        <div className="mt-6 flex rounded-lg border border-casino-border" role="tablist">
          {(['login', 'register'] as const).map((m) => (
            <button
              key={m}
              role="tab"
              aria-selected={mode === m}
              onClick={() => {
                setMode(m);
                setErrors({});
                setServerError(null);
                setInfo(null);
              }}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                mode === m
                  ? 'bg-casino-gold text-black'
                  : 'text-casino-muted hover:text-casino-text'
              }`}
            >
              {m === 'login' ? 'Iniciar sesión' : 'Crear cuenta'}
            </button>
          ))}
        </div>

        <form
          onSubmit={(e) => void handleSubmit(e)}
          className="mt-6 flex flex-col gap-4"
          noValidate
        >
          {mode === 'register' && (
            <div>
              <label htmlFor="username" className="mb-1 block text-sm text-casino-muted">
                Nombre de usuario
              </label>
              <input
                id="username"
                value={form.username}
                onChange={(e) => {
                  set('username', e.target.value);
                }}
                className={inputClass}
                autoComplete="username"
              />
              <FieldError message={errors.username} />
            </div>
          )}

          <div>
            <label htmlFor="email" className="mb-1 block text-sm text-casino-muted">
              Email
            </label>
            <input
              id="email"
              type="email"
              value={form.email}
              onChange={(e) => {
                set('email', e.target.value);
              }}
              className={inputClass}
              autoComplete="email"
            />
            <FieldError message={errors.email} />
          </div>

          <div>
            <label htmlFor="password" className="mb-1 block text-sm text-casino-muted">
              Contraseña
            </label>
            <input
              id="password"
              type="password"
              value={form.password}
              onChange={(e) => {
                set('password', e.target.value);
              }}
              className={inputClass}
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            />
            <FieldError message={errors.password} />
          </div>

          {mode === 'register' && (
            <>
              <div>
                <label htmlFor="confirmPassword" className="mb-1 block text-sm text-casino-muted">
                  Repetir contraseña
                </label>
                <input
                  id="confirmPassword"
                  type="password"
                  value={form.confirmPassword}
                  onChange={(e) => {
                    set('confirmPassword', e.target.value);
                  }}
                  className={inputClass}
                  autoComplete="new-password"
                />
                <FieldError message={errors.confirmPassword} />
              </div>

              <div className="flex flex-col gap-2 text-sm text-casino-muted">
                <label className="flex items-start gap-2">
                  <input
                    type="checkbox"
                    checked={form.acceptAdult}
                    onChange={(e) => {
                      set('acceptAdult', e.target.checked);
                    }}
                    className="mt-1 accent-casino-gold"
                  />
                  Confirmo que soy mayor de 18 años.
                </label>
                <FieldError message={errors.acceptAdult} />
                <label className="flex items-start gap-2">
                  <input
                    type="checkbox"
                    checked={form.acceptTerms}
                    onChange={(e) => {
                      set('acceptTerms', e.target.checked);
                    }}
                    className="mt-1 accent-casino-gold"
                  />
                  Acepto los{' '}
                  <a href="#/terminos" target="_blank" rel="noreferrer" className="underline">
                    términos
                  </a>{' '}
                  y confirmo que entiendo que las fichas son virtuales y sin valor monetario.
                </label>
                <FieldError message={errors.acceptTerms} />
              </div>
            </>
          )}

          {serverError && (
            <p
              role="alert"
              className="rounded-md border border-casino-red/50 bg-casino-red/10 p-3 text-sm text-casino-red"
            >
              {serverError}
            </p>
          )}
          {info && (
            <p
              role="status"
              className="rounded-md border border-casino-green/50 bg-casino-green/10 p-3 text-sm text-casino-green"
            >
              {info}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="rounded-md bg-casino-gold px-4 py-2 font-semibold text-black transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {loading ? 'Cargando…' : mode === 'login' ? 'Entrar' : 'Crear cuenta'}
          </button>
        </form>
      </div>
    </main>
  );
}
