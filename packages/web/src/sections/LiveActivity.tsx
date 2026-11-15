import { useState } from 'react';
import { motion } from 'framer-motion';
import { Dumbbell, Pause, Play, SkipForward } from 'lucide-react';
import { Eyebrow, Phone, Reveal, SectionTitle } from '../site/ui';
import { WORKOUT } from '../site/screens';
import { formatClock, useReducedMotion, useWorkoutClock } from '../site/hooks';

type SessionState = {
  index: number;
  paused: boolean;
  seconds: number;
  next: () => void;
  togglePause: () => void;
};

/** A tiny pretend session so the Live Activity can be tapped. */
function useDemoSession(active: boolean): SessionState {
  const reduced = useReducedMotion();
  const [index, setIndex] = useState(1);
  const [paused, setPaused] = useState(false);
  const seconds = useWorkoutClock(24 * 60 + 18, paused || !active || reduced);
  return {
    index,
    paused,
    seconds,
    next: () => setIndex((i) => (i + 1) % WORKOUT.length),
    togglePause: () => setPaused((p) => !p),
  };
}

function ActivityCard({ s, interactive }: { s: SessionState; interactive: boolean }) {
  const ex = WORKOUT[s.index];
  const btn = 'flex h-9 w-9 items-center justify-center rounded-full transition active:scale-90';
  return (
    <div className="rounded-[1.6rem] border border-white/10 bg-black/55 p-4 text-left shadow-2xl backdrop-blur-xl">
      <div className="mb-2 flex items-center justify-between text-[11px]">
        <span className="flex items-center gap-1.5 font-semibold text-primary-light">
          <Dumbbell className="h-3.5 w-3.5" /> Garage Gym
        </span>
        <span className="text-white/60">
          Exercise {s.index + 1} of {WORKOUT.length}
        </span>
      </div>
      <div className="mb-1 flex items-baseline justify-between gap-3">
        <motion.span key={ex.name} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} className="text-[15px] font-semibold">
          {ex.name}
        </motion.span>
        <span className={`font-mono text-2xl font-medium tabular-nums ${s.paused ? 'text-white/50' : ''}`}>
          {formatClock(s.seconds)}
        </span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-xs text-white/70">
          {ex.sets} sets × {ex.reps} reps · {ex.weight} lbs
        </span>
        <div className="flex gap-2">
          <button
            type="button"
            tabIndex={interactive ? 0 : -1}
            aria-label={s.paused ? 'Resume (demo)' : 'Pause (demo)'}
            onClick={s.togglePause}
            className={`${btn} bg-primary/35 hover:bg-primary/50`}
          >
            {s.paused ? <Play className="h-3.5 w-3.5" /> : <Pause className="h-3.5 w-3.5" />}
          </button>
          <button
            type="button"
            tabIndex={interactive ? 0 : -1}
            aria-label="Next exercise (demo)"
            onClick={s.next}
            className={`${btn} bg-primary hover:brightness-110`}
          >
            <SkipForward className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
      <div className="mt-3 h-1 overflow-hidden rounded-full bg-white/10">
        <motion.div
          className="h-full rounded-full bg-primary"
          animate={{ width: `${((s.index + 1) / WORKOUT.length) * 100}%` }}
          transition={{ type: 'spring', stiffness: 120, damping: 20 }}
        />
      </div>
    </div>
  );
}

/** Dynamic Island: compact pill that expands into the full activity on hover or tap. */
function Island({ s, expanded, onToggle }: { s: SessionState; expanded: boolean; onToggle?: () => void }) {
  const ex = WORKOUT[s.index];
  return (
    <motion.button
      type="button"
      layout
      onClick={onToggle}
      aria-label="Dynamic Island preview"
      aria-expanded={expanded}
      transition={{ type: 'spring', stiffness: 380, damping: 32 }}
      className="mx-auto block overflow-hidden bg-black text-left text-white shadow-[0_25px_60px_-15px_rgba(124,92,250,0.6)] ring-1 ring-white/10"
      style={{ borderRadius: expanded ? 36 : 999, width: expanded ? 340 : 230 }}
    >
      {expanded ? (
        <motion.div layout="position" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="p-5">
          <div className="mb-3 flex items-center justify-between">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/25">
              <Dumbbell className="h-4 w-4 text-primary-light" />
            </span>
            <span className="font-mono text-3xl font-medium tabular-nums text-primary-light">{formatClock(s.seconds)}</span>
          </div>
          <p className="font-semibold">{ex.name}</p>
          <p className="text-sm text-white/60">
            {ex.sets} × {ex.reps} · {ex.weight} lbs · Exercise {s.index + 1} of {WORKOUT.length}
          </p>
        </motion.div>
      ) : (
        <motion.div layout="position" className="flex items-center justify-between px-4 py-2.5">
          <Dumbbell className="h-4 w-4 text-primary-light" />
          <span className="font-mono text-sm font-medium tabular-nums text-primary-light">{formatClock(s.seconds)}</span>
        </motion.div>
      )}
    </motion.button>
  );
}

/** An iPhone Lock Screen with the workout Live Activity on it. */
function LockScreen({ s, interactive, cardBottom = 'bottom-24' }: { s: SessionState; interactive: boolean; cardBottom?: string }) {
  return (
    <div className="relative -mx-4 -mt-14 h-[calc(100%+5rem)] overflow-hidden bg-[radial-gradient(120%_80%_at_20%_0%,#3b2a85_0%,#16121f_55%,#0c0c12_100%)] px-4 pt-16 text-center">
      <div className="absolute left-1/2 top-3 z-30 flex h-[26px] w-[140px] -translate-x-1/2 items-center justify-between rounded-full bg-black px-3">
        <Dumbbell className="h-3 w-3 text-primary-light" />
        <span className="font-mono text-[11px] tabular-nums text-primary-light">{formatClock(s.seconds)}</span>
      </div>
      <p className="text-sm font-semibold text-white/80">Saturday, March 14</p>
      <p className="font-display text-[5.2rem] font-bold leading-none tracking-tight text-white/95">9:41</p>
      <div className={`absolute inset-x-3 ${cardBottom}`}>
        <ActivityCard s={s} interactive={interactive} />
      </div>
      <div className="absolute inset-x-0 bottom-5 mx-auto h-1 w-28 rounded-full bg-white/60" />
    </div>
  );
}

/** A self-running lock screen, used as a step in How it works. */
export function LockScreenScene({ active }: { active: boolean }) {
  const s = useDemoSession(active);
  return <LockScreen s={s} interactive={false} cardBottom="bottom-20" />;
}

export function LiveActivity() {
  const s = useDemoSession(true);
  const [expanded, setExpanded] = useState(false);
  return (
    <section id="live-activity" className="relative scroll-mt-16 overflow-hidden py-28">
      <div aria-hidden className="absolute left-1/2 top-1/3 h-[40rem] w-[40rem] -translate-x-1/2 rounded-full bg-primary/15 blur-[140px]" />
      <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-4 sm:px-8 lg:grid-cols-2">
        <Reveal>
          <Eyebrow>Live Activity · Dynamic Island</Eyebrow>
          <SectionTitle className="mb-6">
            Your workout,
            <br />
            <span className="rk-gradient-text">always in view.</span>
          </SectionTitle>
          <p className="mb-10 max-w-lg text-lg leading-relaxed text-rook-muted">
            Rook’s session timer rides along on your Lock Screen and in the Dynamic Island. Pause, rest, or jump to the
            next lift straight from there. Go ahead, try it.
          </p>
          <div className="rounded-3xl border border-white/[0.07] bg-rook-surface/60 p-8 backdrop-blur">
            <p className="mb-6 text-center text-xs font-semibold uppercase tracking-[0.25em] text-rook-faint">
              Tap the island
            </p>
            <div onMouseEnter={() => setExpanded(true)} onMouseLeave={() => setExpanded(false)} className="flex min-h-[150px] items-center">
              <Island s={s} expanded={expanded} onToggle={() => setExpanded((e) => !e)} />
            </div>
          </div>
        </Reveal>
        <Reveal delayMs={150}>
          <div className="relative">
            <p className="mb-4 text-center text-xs font-semibold uppercase tracking-[0.25em] text-rook-faint lg:hidden">
              Tap pause or next
            </p>
            <Phone>
              <LockScreen s={s} interactive />
            </Phone>
            <p className="mt-6 hidden text-center text-xs font-semibold uppercase tracking-[0.25em] text-rook-faint lg:block">
              ↑ Tap pause or next. It’s live.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
