import { create } from 'zustand';

export type ToastType = 'success' | 'info' | 'error';

export interface Toast {
  id: number;
  type: ToastType;
  text: string;
}

interface ToastState {
  toasts: Toast[];
  push: (type: ToastType, text: string) => void;
  dismiss: (id: number) => void;
}

let nextId = 1;

/** Toasts globales (payout, rondas, mesa…) con auto-expiración. */
export const useToastStore = create<ToastState>((set) => ({
  toasts: [],
  push: (type, text) => {
    const id = nextId++;
    set((s) => ({ toasts: [...s.toasts, { id, type, text }] }));
    setTimeout(() => {
      set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));
    }, 6000);
  },
  dismiss: (id) => {
    set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));
  },
}));

export function toast(type: ToastType, text: string) {
  useToastStore.getState().push(type, text);
}
