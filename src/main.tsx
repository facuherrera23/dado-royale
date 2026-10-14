import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { App } from '@/app/App';

import './index.css';

// Error tracking opcional: activo solo si VITE_SENTRY_DSN está configurado.
if (import.meta.env.VITE_SENTRY_DSN) {
  void import('@sentry/react').then(({ init }) => {
    init({
      dsn: import.meta.env.VITE_SENTRY_DSN as string,
      tracesSampleRate: 0.1,
    });
  });
}

const container = document.getElementById('root');
if (!container) {
  throw new Error('No se encontró el elemento #root en index.html');
}

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
