import { useEffect, useRef } from 'react';

interface AnimatedCounterProps {
  value: number;
  decimals?: number;
  prefix?: string;
  suffix?: string;
}

export default function AnimatedCounter({
  value,
  decimals = 2,
  prefix = '',
  suffix = '',
}: AnimatedCounterProps) {
  const displayRef = useRef<HTMLSpanElement>(null);
  const startRef = useRef(0);
  const rafRef = useRef<number>(0);

  useEffect(() => {
    const start = startRef.current;
    const end = value;
    const duration = 600;
    const startTime = performance.now();

    const animate = (now: number) => {
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = start + (end - start) * eased;

      if (displayRef.current) {
        displayRef.current.textContent = `${prefix}${current.toFixed(decimals)}${suffix}`;
      }

      if (progress < 1) {
        rafRef.current = requestAnimationFrame(animate);
      } else {
        startRef.current = end;
      }
    };

    rafRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(rafRef.current);
  }, [value, decimals, prefix, suffix]);

  return (
    <span ref={displayRef} className="tabular-nums">
      {prefix}{startRef.current.toFixed(decimals)}{suffix}
    </span>
  );
}
