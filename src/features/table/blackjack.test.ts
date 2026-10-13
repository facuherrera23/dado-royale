import { describe, expect, it } from 'vitest';

import { cardRank, cardSuit, handValue, rankLabel } from './blackjack';

describe('blackjack (presentación, misma regla que el servidor)', () => {
  it('cardRank/cardSuit descomponen la baraja 1..52', () => {
    expect(cardRank(1)).toBe(2);
    expect(cardRank(13)).toBe(14); // A de picas
    expect(cardSuit(13)).toBe('♠');
    expect(cardSuit(52)).toBe('♣');
    expect(rankLabel(14)).toBe('A');
  });

  it('figuras valen 10 y el as 11', () => {
    expect(handValue([13, 38])).toBe(21); // A + K
    expect(handValue([11, 12])).toBe(20); // J + Q
  });

  it('ases flexibles: A+A = 12 y nunca pasa de 21 si puede', () => {
    expect(handValue([13, 26])).toBe(12); // A + A
    expect(handValue([13, 26, 3])).toBe(16); // A + A + 4 (11+1+4)
    expect(handValue([13, 3, 12])).toBe(15); // A + 4 + Q = 25 -> 15
  });

  it('se pasa si no queda remedio', () => {
    expect(handValue([12, 11, 10])).toBe(30);
  });
});
