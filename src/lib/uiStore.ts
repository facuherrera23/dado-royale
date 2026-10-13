import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface UiState {
  muted: boolean;
  ambient: boolean;
  toggleMuted: () => void;
  toggleAmbient: () => void;
}

/** Preferencias de UI (persisten en localStorage). */
export const useUiStore = create<UiState>()(
  persist(
    (set) => ({
      muted: false,
      ambient: false,
      toggleMuted: () => {
        set((s) => ({ muted: !s.muted }));
      },
      toggleAmbient: () => {
        set((s) => ({ ambient: !s.ambient }));
      },
    }),
    { name: 'dado-royale-ui' },
  ),
);
