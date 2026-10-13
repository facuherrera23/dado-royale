import { motion } from 'framer-motion';

/** Posiciones de los puntos en una rejilla 3×3 para cada cara del dado. */
const PIPS: Record<number, [row: number, col: number][]> = {
  1: [[2, 2]],
  2: [
    [1, 1],
    [3, 3],
  ],
  3: [
    [1, 1],
    [2, 2],
    [3, 3],
  ],
  4: [
    [1, 1],
    [1, 3],
    [3, 1],
    [3, 3],
  ],
  5: [
    [1, 1],
    [1, 3],
    [2, 2],
    [3, 1],
    [3, 3],
  ],
  6: [
    [1, 1],
    [1, 3],
    [2, 1],
    [2, 3],
    [3, 1],
    [3, 3],
  ],
};

/**
 * Dado D6 con animación de "tirada" al cambiar de valor.
 * value = null muestra el estado "sin lanzar".
 */
export function Dice({ value, label }: { value: number | null; label: string }) {
  const isRolled = value !== null && value >= 1 && value <= 6;
  return (
    <div role="img" aria-label={`Dado ${label}: ${isRolled ? String(value) : 'sin lanzar'}`}>
      <motion.div
        key={isRolled ? `v${String(value)}` : 'pending'}
        initial={{ rotate: isRolled ? -270 : 0, scale: 0.6, opacity: 0.4 }}
        animate={{ rotate: 0, scale: 1, opacity: 1 }}
        transition={{ type: 'spring', stiffness: 380, damping: 18 }}
        className={`grid h-14 w-14 grid-cols-3 grid-rows-3 gap-0.5 rounded-lg border-2 p-1.5 shadow-lg ${
          isRolled ? 'border-casino-gold/60 bg-white' : 'border-casino-border bg-casino-surface'
        }`}
      >
        {isRolled
          ? Array.from({ length: 9 }, (_, i) => {
              const row = Math.floor(i / 3) + 1;
              const col = (i % 3) + 1;
              const on = PIPS[value].some(([r, c]) => r === row && c === col);
              return (
                <span key={i} className={`rounded-full ${on ? 'bg-gray-900' : 'bg-transparent'}`} />
              );
            })
          : Array.from({ length: 9 }, (_, i) => (
              <span
                key={i}
                className={i === 4 ? 'text-center text-base leading-none text-casino-muted' : ''}
              >
                {i === 4 ? '?' : ''}
              </span>
            ))}
      </motion.div>
    </div>
  );
}
