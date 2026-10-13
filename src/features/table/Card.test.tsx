import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { Card } from './Card';

describe('Card', () => {
  it('muestra el dorso sin valor', () => {
    render(<Card value={null} label="1" />);
    expect(screen.getByRole('img', { name: 'Carta 1: boca abajo' })).toBeInTheDocument();
  });

  it('muestra el as de picas (1..52 => A♠ es la 13)', () => {
    render(<Card value={13} label="1" />);
    expect(screen.getByRole('img', { name: 'Carta 1: A♠' })).toBeInTheDocument();
  });

  it('muestra la K de corazones (25)', () => {
    render(<Card value={25} label="2" />);
    expect(screen.getByRole('img', { name: 'Carta 2: K♥' })).toBeInTheDocument();
  });
});
