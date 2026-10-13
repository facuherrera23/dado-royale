import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface UiState {
  muted: boolean;
  toggleMuted: () => void;
}

/** Preferencias de UI (persisten en localStorage). */
export const useUiStore = create<UiState>()(
  persist(
    (set) => ({
      muted: false,
      toggleMuted: () => {
        set((s) => ({ muted: !s.muted }));
      },
    }),
    { name: 'dado-royale-ui' },
  ),
);
