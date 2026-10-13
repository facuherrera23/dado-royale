import type { RoundPlayer } from './useRound';

const FACES: Record<number, string> = { 11: 'J', 12: 'Q', 13: 'K', 14: 'A' };
const SUITS = ['♠', '♥', '♦', '♣'] as const;

/** rank 2..14 y palo 0..3 (solo presentación; el servidor decide). */
export function cardRank(card: number): number {
  return ((card - 1) % 13) + 2;
}
export function cardSuit(card: number): (typeof SUITS)[number] {
  return SUITS[Math.floor((card - 1) / 13)];
}
export function rankLabel(r: number): string {
  return FACES[r] ?? String(r);
}

/** Valor de la mano con ases flexibles (misma regla que el servidor). */
export function handValue(cards: number[]): number {
  let total = cards.reduce<number>(
    (acc, c) => acc + (cardRank(c) === 14 ? 11 : Math.min(cardRank(c), 10)),
    0,
  );
  let aces = cards.filter((c) => cardRank(c) === 14).length;
  while (total > 21 && aces > 0) {
    total -= 10;
    aces -= 1;
  }
  return total;
}

/** Texto descriptivo de la mano (solo presentación). */
export function describeHand(p: RoundPlayer): string {
  const value = handValue(p.cards);
  if (p.result === 'blackjack') return '¡BLACKJACK!';
  if (value > 21) return `Se pasó (${String(value)})`;
  return `Total: ${String(value)}`;
}

export const RESULT_LABELS: Record<string, string> = {
  win: '¡Ganaste!',
  blackjack: '¡Blackjack! Paga 3:2',
  push: 'Push — te devuelven la apuesta',
  loss: 'La banca gana',
};
