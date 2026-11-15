import { useRef } from 'react';
import { Asterisk } from 'lucide-react';
import { useCountUp, useInView } from '../site/hooks';
import { Reveal } from '../site/ui';

const LIFTS = [
  'Back Squat',
  'Bench Press',
  'Deadlift',
  'Overhead Press',
  'Pull-Up',
  'Romanian Deadlift',
  'Hip Thrust',
  'Barbell Row',
  'Incline Press',
  'Sauna',
  'Lateral Raise',
  'Goblet Squat',
];

function Row({ words, reverse = false, outline = false }: { words: string[]; reverse?: boolean; outline?: boolean }) {
  const items = [...words, ...words];
  return (
    <div className="rk-marquee overflow-hidden py-3">
      <div className={`rk-marquee-track flex w-max items-center gap-8 ${reverse ? 'rk-reverse' : ''}`}>
        {items.map((w, i) => (
          <span key={i} className="flex items-center gap-8" aria-hidden={i >= words.length}>
            <span
              className={`font-display text-4xl font-extrabold uppercase tracking-tight sm:text-6xl ${
                outline ? 'text-transparent [-webkit-text-stroke:1.5px_rgba(255,255,255,0.22)]' : 'text-white/90'
              }`}
            >
              {w}
            </span>
            <Asterisk className={`h-7 w-7 shrink-0 ${outline ? 'text-white/20' : 'text-primary'}`} />
          </span>
        ))}
      </div>
    </div>
  );
}

/** A slanted ribbon of lifts scrolling in opposite directions. */
export function LiftMarquee() {
  return (
    <section aria-label="Every lift you do" className="relative -my-6 overflow-hidden py-16">
      <div className="-rotate-2 border-y border-white/[0.06] bg-rook-canvas/60 backdrop-blur">
        <Row words={LIFTS} />
        <Row words={[...LIFTS].reverse()} reverse outline />
      </div>
    </section>
  );
}

const STATS = [
  { value: 1, suffix: ' tap', label: 'to repeat any recent workout, sets and weights included' },
  { value: 5, suffix: '', label: 'quick-weight buttons so you never type between sets' },
  { value: 0, suffix: ' unlocks', label: 'needed to pause or skip. It all works from the Lock Screen' },
  { value: 4, suffix: '', label: 'home-screen widgets to keep your streak in sight' },
];

function Stat({ value, suffix, label, active }: { value: number; suffix: string; label: string; active: boolean }) {
  const n = useCountUp(value, active, 1400);
  return (
    <div className="border-l border-white/10 pl-5">
      <p className="font-display text-5xl font-extrabold tabular-nums tracking-tight sm:text-6xl">
        {Math.round(n)}
        <span className="text-2xl text-primary-light sm:text-3xl">{suffix}</span>
      </p>
      <p className="mt-2 text-sm leading-relaxed text-rook-muted">{label}</p>
    </div>
  );
}

/** Product facts that count up as they come into view. */
export function StatsBand() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, 0.4);
  return (
    <section className="mx-auto max-w-6xl px-4 py-24 sm:px-8">
      <Reveal>
        <div ref={ref} className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
          {STATS.map((s) => (
            <Stat key={s.label} {...s} active={inView} />
          ))}
        </div>
      </Reveal>
    </section>
  );
}
