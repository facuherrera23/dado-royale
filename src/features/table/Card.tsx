import { motion } from 'framer-motion';

const RANKS: Record<number, string> = {
  11: 'J',
  12: 'Q',
  13: 'K',
  14: 'A',
};
const SUITS = ['♠', '♥', '♦', '♣'] as const;
const SUIT_COLOR = (s: number) => (s === 1 || s === 2 ? 'text-red-600' : 'text-gray-900');

function rankOf(card: number): number {
  return ((card - 1) % 13) + 2;
}
function suitOf(card: number): number {
  return Math.floor((card - 1) / 13);
}

/** Carta de poker (1..52). value = null muestra el dorso. */
export function Card({ value, label }: { value: number | null; label: string }) {
  const faceUp = value !== null && value >= 1 && value <= 52;
  const rank = faceUp ? (RANKS[rankOf(value)] ?? String(rankOf(value))) : null;
  const suit = faceUp ? SUITS[suitOf(value)] : null;

  return (
    <div
      role="img"
      aria-label={`Carta ${label}: ${faceUp ? `${rank ?? ''}${suit ?? ''}` : 'boca abajo'}`}
    >
      <motion.div
        key={faceUp ? `c${String(value)}` : 'down'}
        initial={{ rotateY: 90, scale: 0.9, opacity: 0.5 }}
        animate={{ rotateY: 0, scale: 1, opacity: 1 }}
        transition={{ type: 'spring', stiffness: 300, damping: 20 }}
        className={`flex h-20 w-14 flex-col justify-between rounded-lg border-2 p-1.5 shadow-lg ${
          faceUp ? 'border-casino-gold/60 bg-white' : 'border-casino-border bg-casino-gold/20'
        }`}
      >
        {faceUp ? (
          <>
            <span
              className={`text-left text-sm font-bold leading-none ${SUIT_COLOR(suitOf(value))}`}
            >
              {rank}
            </span>
            <span className={`text-center text-2xl leading-none ${SUIT_COLOR(suitOf(value))}`}>
              {suit}
            </span>
            <span
              className={`rotate-180 text-left text-sm font-bold leading-none ${SUIT_COLOR(suitOf(value))}`}
            >
              {rank}
            </span>
          </>
        ) : (
          <span className="h-full w-full rounded-sm border border-casino-gold/40 bg-repeating-linear" />
        )}
      </motion.div>
    </div>
  );
}
