import { useState } from 'react';

import { z } from 'zod';

import { useSetBet } from './useRound';

interface Props {
  tableId: string;
  min: number;
  max: number;
  current: number | null;
}

/** Selector de apuesta para mesas de blackjack (validado con Zod y en el servidor). */
export function BetSetter({ tableId, min, max, current }: Props) {
  const [raw, setRaw] = useState(current?.toString() ?? String(min));
  const [error, setError] = useState<string | null>(null);
  const setBet = useSetBet(tableId);

  const schema = z
    .number({ error: 'Introduce un número' })
    .int('Solo números enteros')
    .min(min, `Mínimo ${String(min)} 🪙`)
    .max(max, `Máximo ${String(max)} 🪙`);

  const submit = (e: React.SyntheticEvent) => {
    e.preventDefault();
    const parsed = schema.safeParse(Number(raw));
    if (!parsed.success) {
      setError(parsed.error.issues[0].message);
      return;
    }
    setError(null);
    setBet.mutate(parsed.data);
  };

  return (
    <form onSubmit={submit} className="flex flex-wrap items-end gap-3" noValidate>
      <div>
        <label htmlFor="bet" className="mb-1 block text-sm text-casino-muted">
          Tu apuesta ({min}–{max} 🪙)
        </label>
        <input
          id="bet"
          type="number"
          inputMode="numeric"
          min={min}
          max={max}
          value={raw}
          onChange={(e) => {
            setRaw(e.target.value);
          }}
          className="w-32 rounded-md border border-casino-border bg-casino-bg px-3 py-2 text-casino-text focus:border-casino-gold focus:outline-none focus:ring-1 focus:ring-casino-gold"
        />
      </div>
      <button
        type="submit"
        disabled={setBet.isPending}
        className="rounded-md bg-casino-green px-4 py-2 font-semibold text-white transition-opacity enabled:hover:opacity-90 disabled:opacity-40"
      >
        {setBet.isPending ? 'Fijando…' : current ? 'Cambiar apuesta' : 'Fijar apuesta'}
      </button>
      {error && (
        <p role="alert" className="w-full text-sm text-casino-red">
          {error}
        </p>
      )}
      {setBet.isError && (
        <p role="alert" className="w-full text-sm text-casino-red">
          {setBet.error.message}
        </p>
      )}
    </form>
  );
}
