import { AnimatePresence, motion } from 'framer-motion';

import { useToastStore } from '@/lib/toastStore';

const ICONS = { success: '✅', info: 'ℹ️', error: '⚠️' } as const;

/** Notificaciones flotantes (toast) globales. */
export function Toaster() {
  const { toasts, dismiss } = useToastStore();

  return (
    <div
      aria-live="polite"
      aria-label="Notificaciones"
      className="pointer-events-none fixed bottom-4 right-4 z-50 flex w-80 flex-col gap-2"
    >
      <AnimatePresence>
        {toasts.map((t) => (
          <motion.button
            key={t.id}
            initial={{ opacity: 0, x: 60, scale: 0.95 }}
            animate={{ opacity: 1, x: 0, scale: 1 }}
            exit={{ opacity: 0, x: 40 }}
            onClick={() => {
              dismiss(t.id);
            }}
            className={`pointer-events-auto rounded-lg border p-3 text-left text-sm shadow-xl ${
              t.type === 'success'
                ? 'border-casino-green/60 bg-casino-green/10 text-casino-green'
                : t.type === 'error'
                  ? 'border-casino-red/60 bg-casino-red/10 text-casino-red'
                  : 'border-casino-gold/60 bg-casino-surface text-casino-text'
            }`}
          >
            {ICONS[t.type]} {t.text}
          </motion.button>
        ))}
      </AnimatePresence>
    </div>
  );
}
