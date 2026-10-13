import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { Dice } from './Dice';

describe('Dice', () => {
  it('muestra estado pendiente sin valor', () => {
    render(<Dice value={null} label="1" />);
    expect(screen.getByRole('img', { name: 'Dado 1: sin lanzar' })).toBeInTheDocument();
  });

  it.each([1, 2, 3, 4, 5, 6])('muestra la cara %i', (value) => {
    render(<Dice value={value} label="2" />);
    expect(screen.getByRole('img', { name: `Dado 2: ${String(value)}` })).toBeInTheDocument();
  });
});
