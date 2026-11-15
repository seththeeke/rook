import type { ReactNode } from 'react';
import { motion } from 'framer-motion';
import { Dumbbell, Flame, Trophy } from 'lucide-react';
import { PulseCanvas } from './PulseCanvas';
import { EarlyAccessButton, Phone } from '../site/ui';
import { DashboardScreen } from '../site/screens';
import { formatClock, useReducedMotion, useWorkoutClock } from '../site/hooks';

const HEADLINE = [['Build', 'it.'], ['Start', 'it.'], ['Log', 'every', 'rep.']];
const WORD_DELAY_MS = 90;
const LINE_PAUSE_MS = 220;

/** The headline, word by word: each word rises out of a blur, and the last line shimmers. */
function KineticHeadline() {
  let index = 0;
  return (
    <h1
      aria-label={HEADLINE.map((l) => l.join(' ')).join(' ')}
      className="font-display text-[3.4rem] font-black leading-[0.92] tracking-[-0.03em] sm:text-7xl lg:text-[5.75rem]"
    >
      {HEADLINE.map((line, li) => (
        <span key={li} aria-hidden className="block">
          {line.map((word) => {
            const delay = index * WORD_DELAY_MS + li * LINE_PAUSE_MS;
            index += 1;
            return (
              <span
                key={word}
                className="mr-[0.22em] inline-block animate-[rk-rise_0.9s_cubic-bezier(0.2,0.8,0.2,1)_both]"
                style={{ animationDelay: `${delay}ms` }}
              >
                <span className={li === HEADLINE.length - 1 ? 'rk-gradient-text' : undefined}>{word}</span>
              </span>
            );
          })}
        </span>
      ))}
    </h1>
  );
}

function FloatingIsland() {
  const reduced = useReducedMotion();
  const seconds = useWorkoutClock(18 * 60 + 4, reduced);
  return (
    <div className="flex items-center gap-6 rounded-full bg-black px-4 py-2.5 shadow-[0_20px_50px_-10px_rgba(0,0,0,0.9)] ring-1 ring-white/10">
      <span className="flex h-5 w-5 items-center justify-center rounded-full bg-primary/30">
        <Dumbbell className="h-3 w-3 text-primary-light" />
      </span>
      <span className="font-mono text-sm font-medium tabular-nums text-primary-light">{formatClock(seconds)}</span>
    </div>
  );
}

function Chip({ children, className }: { children: ReactNode; className: string }) {
  return (
    <div
      className={`absolute z-20 hidden items-center gap-2 rounded-2xl border border-white/10 bg-rook-surface/80 px-3.5 py-2.5 text-sm font-semibold shadow-2xl backdrop-blur-md sm:flex ${className}`}
    >
      {children}
    </div>
  );
}

export function Hero() {
  return (
    <section className="relative flex min-h-[100svh] items-center overflow-hidden pt-16">
      <PulseCanvas />
      <div aria-hidden className="rk-vignette pointer-events-none absolute inset-0" />

      <div className="relative mx-auto grid w-full max-w-6xl items-center gap-14 px-4 py-16 sm:px-8 lg:grid-cols-[1.15fr_0.85fr]">
        <div>
          <p
            className="mb-6 inline-flex animate-[rk-rise_0.8s_ease-out_both] items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 text-xs font-semibold text-rook-muted backdrop-blur"
          >
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-[rk-ping_1.4s_ease-out_infinite] rounded-full bg-mint" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-mint" />
            </span>
            Now in early access for iPhone
          </p>
          <KineticHeadline />
          <p
            className="mt-8 max-w-xl animate-[rk-rise_0.9s_ease-out_both] text-lg leading-relaxed text-rook-muted sm:text-xl"
            style={{ animationDelay: '900ms' }}
          >
            Rook builds your workout with AI, runs it from your Lock Screen and Dynamic Island, and keeps score of every
            streak and PR, so all you have to do is lift.
          </p>
          <div
            className="mt-10 flex animate-[rk-rise_0.9s_ease-out_both] flex-wrap items-center gap-x-8 gap-y-5"
            style={{ animationDelay: '1100ms' }}
          >
            <EarlyAccessButton />
            <a
              href="#how-it-works"
              className="text-base font-medium text-rook-muted underline-offset-8 transition hover:text-white hover:underline"
            >
              See how it works
            </a>
          </div>
        </div>

        <motion.div
          className="relative mx-auto"
          initial={{ opacity: 0, y: 40, rotate: -4 }}
          animate={{ opacity: 1, y: 0, rotate: 0 }}
          transition={{ duration: 1.1, delay: 0.5, ease: [0.22, 1, 0.36, 1] }}
        >
          <div aria-hidden className="absolute -inset-10 rounded-full bg-primary/25 blur-[90px]" />
          <div className="absolute -top-7 left-1/2 z-30 -translate-x-1/2">
            <FloatingIsland />
          </div>
          <div className="animate-[rk-float_7s_ease-in-out_infinite]">
            <Phone>
              <DashboardScreen />
            </Phone>
          </div>
          <Chip className="-left-24 top-28 animate-[rk-float_6s_ease-in-out_infinite]">
            <Flame className="h-4 w-4 text-heat" /> 12-day streak
          </Chip>
          <Chip className="-right-24 bottom-10 animate-[rk-float_8s_ease-in-out_infinite_1s]">
            <Trophy className="h-4 w-4 text-gold" /> New PR · 225 lb
          </Chip>
        </motion.div>
      </div>

      <div aria-hidden className="absolute bottom-6 left-1/2 hidden -translate-x-1/2 animate-[rk-float_2.4s_ease-in-out_infinite] md:block">
        <span className="block h-10 w-6 rounded-full border-2 border-white/20">
          <span className="mx-auto mt-2 block h-2 w-1 rounded-full bg-white/40" />
        </span>
      </div>
    </section>
  );
}
