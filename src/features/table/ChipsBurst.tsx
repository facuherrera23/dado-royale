import { motion } from 'framer-motion';

/** Lluvia de fichas al ganar (decorativa, respeta prefers-reduced-motion). */
export function ChipsBurst() {
  const chips = Array.from({ length: 14 }, (_, i) => {
    const angle = (i / 14) * Math.PI * 2;
    return {
      x: Math.cos(angle) * (90 + (i % 4) * 25),
      y: Math.sin(angle) * (60 + (i % 3) * 20) - 40,
      delay: (i % 5) * 0.05,
      dur: 0.8 + (i % 4) * 0.15,
    };
  });

  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true">
      {chips.map((c, i) => (
        <motion.span
          key={i}
          initial={{ x: 0, y: 0, opacity: 1, scale: 0.4 }}
          animate={{ x: c.x, y: c.y, opacity: 0, scale: 1.1, rotate: 360 }}
          transition={{ duration: c.dur, delay: c.delay, ease: 'easeOut' }}
          className="absolute left-1/2 top-1/2 text-xl motion-reduce:hidden"
        >
          🪙
        </motion.span>
      ))}
    </div>
  );
}
