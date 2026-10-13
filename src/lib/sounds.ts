import { useUiStore } from './uiStore';

/**
 * Efectos de sonido ligeros con WebAudio (sin assets de audio).
 * Todos respetan el mute global de uiStore.
 */

let ctx: AudioContext | null = null;

function audio(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  ctx ??= new AudioContext();
  if (ctx.state === 'suspended') void ctx.resume();
  return ctx;
}

function tone(
  freq: number,
  durationMs: number,
  type: OscillatorType = 'sine',
  gain = 0.08,
  when = 0,
) {
  if (useUiStore.getState().muted) return;
  const ac = audio();
  if (!ac) return;
  const osc = ac.createOscillator();
  const g = ac.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  const start = ac.currentTime + when;
  g.gain.setValueAtTime(gain, start);
  g.gain.exponentialRampToValueAtTime(0.0001, start + durationMs / 1000);
  osc.connect(g).connect(ac.destination);
  osc.start(start);
  osc.stop(start + durationMs / 1000);
}

/** Fichas al apostar/cobrar */
export function playChip() {
  tone(1300, 60, 'triangle', 0.09, 0);
  tone(950, 70, 'triangle', 0.08, 0.06);
  tone(1500, 80, 'triangle', 0.07, 0.12);
}

/** Dados rodando */
export function playDice() {
  for (let i = 0; i < 4; i++) tone(400 + i * 120, 45, 'square', 0.05, i * 0.05);
}

/** Carta repartida */
export function playCard() {
  tone(700, 40, 'sawtooth', 0.03, 0);
  tone(500, 55, 'triangle', 0.06, 0.03);
}

/** Victoria en una ronda */
export function playWin() {
  [523, 659, 784, 1047].forEach((f, i) => {
    tone(f, 180, 'triangle', 0.09, i * 0.12);
  });
}

/** Derrota suave */
export function playLose() {
  tone(300, 220, 'sine', 0.07, 0);
  tone(220, 300, 'sine', 0.07, 0.18);
}

// -----------------------------------------------------------------
// Sonido ambiente de casino: ruido marrón filtrado, en loop y muy suave
// -----------------------------------------------------------------
let ambientNodes: { source: AudioBufferSourceNode; gain: GainNode } | null = null;

function buildNoiseBuffer(ac: AudioContext): AudioBuffer {
  const seconds = 4;
  const buffer = ac.createBuffer(1, ac.sampleRate * seconds, ac.sampleRate);
  const data = buffer.getChannelData(0);
  let last = 0;
  for (let i = 0; i < data.length; i++) {
    const white = Math.random() * 2 - 1;
    last = (last + 0.02 * white) / 1.02; // brown noise
    data[i] = last * 3.5;
  }
  return buffer;
}

export function startAmbient() {
  if (useUiStore.getState().muted || ambientNodes) return;
  const ac = audio();
  if (!ac) return;
  const source = ac.createBufferSource();
  source.buffer = buildNoiseBuffer(ac);
  source.loop = true;
  const filter = ac.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 400;
  const gain = ac.createGain();
  gain.gain.value = 0.012;
  source.connect(filter).connect(gain).connect(ac.destination);
  source.start();
  ambientNodes = { source, gain };
}

export function stopAmbient() {
  if (!ambientNodes) return;
  try {
    ambientNodes.source.stop();
  } catch {
    /* ya detenido */
  }
  ambientNodes = null;
}

/** Sincroniza el ambiente con las preferencias y el mute global. */
export function syncAmbient() {
  const { muted, ambient } = useUiStore.getState();
  if (ambient && !muted) startAmbient();
  else stopAmbient();
}
