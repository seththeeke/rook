import { useEffect, useState } from 'react';
import { Check, Dumbbell, Flame, Footprints, Pause, Sparkles, Trophy, Zap } from 'lucide-react';
import { Card } from './ui';
import { formatClock, useReducedMotion, useTypewriter, useWorkoutClock } from './hooks';

/*
 * Illustrations of the real iOS screens, built in HTML so they stay crisp and can move.
 * Each takes `active`, which starts its animation when the screen is on stage.
 */

export const WORKOUT = [
  { name: 'Barbell Bench Press', sets: 4, reps: 6, weight: 185 },
  { name: 'Incline Dumbbell Press', sets: 3, reps: 10, weight: 60 },
  { name: 'Weighted Pull-Up', sets: 4, reps: 6, weight: 25 },
  { name: 'Seated Cable Row', sets: 3, reps: 12, weight: 140 },
  { name: 'Lateral Raise', sets: 3, reps: 15, weight: 20 },
  { name: 'Triceps Pushdown', sets: 3, reps: 12, weight: 55 },
];

const WEEK = [
  { d: 'M', done: true },
  { d: 'T', done: false },
  { d: 'W', done: true },
  { d: 'T', done: true },
  { d: 'F', done: true },
  { d: 'S', done: false, today: true },
  { d: 'S', done: false },
];

export function WeekStrip({ fillToday = false, compact = false }: { fillToday?: boolean; compact?: boolean }) {
  return (
    <div className="flex justify-between">
      {WEEK.map((day, i) => {
        const done = day.done || (fillToday && day.today);
        return (
          <div key={i} className="flex flex-col items-center gap-1.5">
            <div
              className={`flex items-center justify-center rounded-full border transition-all duration-500 ${
                compact ? 'h-5 w-5 sm:h-7 sm:w-7' : 'h-7 w-7'
              } ${
                done
                  ? 'border-transparent bg-primary shadow-[0_0_14px_rgba(124,92,250,0.6)]'
                  : day.today
                    ? 'border-primary bg-primary/10'
                    : 'border-white/[0.07] bg-rook-elevated'
              }`}
            >
              {done && <Check className={compact ? 'h-3 w-3 sm:h-3.5 sm:w-3.5' : 'h-3.5 w-3.5'} strokeWidth={3} />}
            </div>
            <span className={`text-[9px] ${day.today ? 'font-bold text-primary-light' : 'text-rook-muted'}`}>{day.d}</span>
          </div>
        );
      })}
    </div>
  );
}

export function DashboardScreen() {
  return (
    <div className="space-y-3 text-left">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs text-rook-muted">Welcome back,</p>
          <p className="font-display text-2xl font-bold">Alex</p>
        </div>
        <div className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-rook-elevated text-sm font-semibold">
          A
        </div>
      </div>
      <Card className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-heat/15">
          <Flame className="h-5 w-5 text-heat" />
        </div>
        <div className="flex-1">
          <p className="text-[10px] text-rook-muted">Current Streak</p>
          <p className="text-lg font-bold">12 days</p>
        </div>
        <div className="text-right">
          <p className="text-[10px] text-rook-muted">Best</p>
          <p className="text-sm font-semibold text-primary-light">21 days</p>
        </div>
      </Card>
      <div className="grid grid-cols-3 gap-2">
        {[
          { icon: <Dumbbell className="h-4 w-4 text-primary-light" />, v: '48', l: 'Workouts' },
          { icon: <Zap className="h-4 w-4 text-gold" />, v: '13', l: 'Last 30d' },
          { icon: <Footprints className="h-4 w-4 text-mint" />, v: '8.2k', l: 'Steps' },
        ].map((s) => (
          <Card key={s.l} className="!p-3">
            {s.icon}
            <p className="mt-1.5 text-lg font-bold">{s.v}</p>
            <p className="text-[10px] text-rook-muted">{s.l}</p>
          </Card>
        ))}
      </div>
      <Card>
        <p className="mb-3 text-sm font-semibold">This Week</p>
        <WeekStrip />
      </Card>
      <Card className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Trophy className="h-4 w-4 text-gold" />
          <div>
            <p className="text-[10px] text-rook-muted">Personal Record</p>
            <p className="text-sm font-semibold">Bench Press</p>
          </div>
        </div>
        <p className="text-sm font-bold">225 lbs</p>
      </Card>
      <div className="rounded-2xl bg-gradient-to-br from-[#8B6CFF] to-[#6A4BE8] py-3 text-center text-sm font-semibold shadow-lg shadow-primary/40">
        Start Workout
      </div>
    </div>
  );
}

const PROMPT = 'Upper body push and pull, 45 minutes';

export function BuilderScreen({ active }: { active: boolean }) {
  const typed = useTypewriter(PROMPT, active, 38);
  const done = typed.length === PROMPT.length;
  const reduced = useReducedMotion();
  const [shown, setShown] = useState(0);

  useEffect(() => {
    if (!done) {
      setShown(0);
      return;
    }
    if (reduced) {
      setShown(WORKOUT.length);
      return;
    }
    const id = window.setInterval(() => setShown((n) => (n >= WORKOUT.length ? n : n + 1)), 260);
    return () => window.clearInterval(id);
  }, [done, reduced]);

  return (
    <div className="text-left">
      <p className="font-display text-xl font-bold">Build with AI</p>
      <p className="mb-3 text-[11px] text-rook-muted">Garage Gym · barbell, dumbbells, cable, pull-up bar</p>
      <div className="mb-4 rounded-2xl border border-primary/40 bg-primary/10 p-3 text-sm">
        <span className={done ? '' : 'rk-caret'}>{typed}</span>
      </div>
      <div className="mb-2 flex items-center gap-2 text-[11px] text-primary-light">
        <Sparkles className={`h-3.5 w-3.5 ${done && shown < WORKOUT.length ? 'animate-spin' : ''}`} />
        {done ? (shown < WORKOUT.length ? 'Building your workout…' : '6 exercises · about 45 min') : 'Describe your session'}
      </div>
      <div className="space-y-1.5">
        {WORKOUT.map((ex, i) => (
          <div
            key={ex.name}
            className={`flex items-center justify-between rounded-xl border border-white/[0.07] bg-rook-surface px-3 py-2 transition-all duration-500 ${
              i < shown ? 'translate-y-0 opacity-100' : 'translate-y-2 opacity-0'
            }`}
          >
            <div>
              <p className="text-[12px] font-semibold">{ex.name}</p>
              <p className="text-[10px] text-rook-muted">
                {ex.sets} × {ex.reps}
              </p>
            </div>
            <span className="text-[11px] font-semibold text-rook-muted">{ex.weight} lb</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const BUMPS = [-5, 5, 10, 25, 50];

export function ExecutionScreen({ active }: { active: boolean }) {
  const reduced = useReducedMotion();
  const seconds = useWorkoutClock(24 * 60 + 18, !active || reduced);
  const [weight, setWeight] = useState(185);
  const [pressed, setPressed] = useState<number | null>(null);

  // Auto-demo: tap +5 then +10 so the quick-adjust buttons read at a glance.
  useEffect(() => {
    if (!active || reduced) return;
    const steps = [5, 10, -5, 5];
    let i = 0;
    const id = window.setInterval(() => {
      const bump = steps[i % steps.length];
      setPressed(bump);
      setWeight((w) => w + bump);
      window.setTimeout(() => setPressed(null), 220);
      i += 1;
    }, 1600);
    return () => window.clearInterval(id);
  }, [active, reduced]);

  return (
    <div className="text-center">
      <div className="mb-3 flex items-center justify-between">
        <div className="h-8 w-8" />
        <p className="font-mono text-2xl font-medium tabular-nums">{formatClock(seconds)}</p>
        <div className="flex h-8 w-8 items-center justify-center rounded-full border border-white/10 bg-rook-elevated">
          <Pause className="h-3.5 w-3.5" />
        </div>
      </div>
      <p className="mb-1.5 text-left text-[10px] text-rook-muted">Exercise 1 of 6</p>
      <div className="mb-7 h-1 overflow-hidden rounded-full bg-rook-elevated">
        <div className="h-full w-1/6 rounded-full bg-primary" />
      </div>
      <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-[#8B6CFF] to-[#6A4BE8] shadow-lg shadow-primary/40">
        <Dumbbell className="h-7 w-7" />
      </div>
      <p className="font-display text-xl font-bold">Barbell Bench Press</p>
      <p className="mb-5 text-xs text-rook-muted">4 sets × 6 reps</p>
      <Card className="mb-5">
        <p className="mb-1 text-[10px] text-rook-muted">Weight (lbs)</p>
        <p key={weight} className="mb-3 animate-[rk-rise_0.35s_ease-out_both] font-display text-5xl font-bold tabular-nums">
          {weight}
        </p>
        <div className="grid grid-cols-5 gap-1">
          {BUMPS.map((b) => (
            <button
              key={b}
              type="button"
              tabIndex={-1}
              onClick={() => setWeight((w) => Math.max(0, w + b))}
              className={`rounded-lg border py-1.5 text-[11px] font-semibold transition ${
                pressed === b
                  ? 'scale-90 border-primary bg-primary/40'
                  : 'border-white/[0.07] bg-rook-elevated hover:bg-white/10'
              } ${b < 0 ? 'text-rook-muted' : ''}`}
            >
              {b < 0 ? `−${-b}` : `+${b}`}
            </button>
          ))}
        </div>
      </Card>
      <div className="flex gap-2">
        <div className="flex-1 rounded-xl border border-white/[0.07] bg-rook-elevated py-3 text-sm font-semibold">Previous</div>
        <div className="flex-1 rounded-xl bg-gradient-to-br from-[#8B6CFF] to-[#6A4BE8] py-3 text-sm font-semibold">Next</div>
      </div>
    </div>
  );
}

export function ProgressScreen({ active }: { active: boolean }) {
  return (
    <div className="flex h-full flex-col items-center justify-center text-center">
      <div className="relative mb-5">
        <div
          className={`absolute inset-0 rounded-full bg-gold/30 ${active ? 'animate-[rk-ping_1.6s_ease-out_infinite]' : ''}`}
        />
        <div className="relative flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-gold to-heat shadow-[0_0_60px_rgba(255,201,77,0.5)]">
          <Trophy className="h-9 w-9 text-rook-ink" />
        </div>
      </div>
      <p className="text-xs font-semibold uppercase tracking-[0.3em] text-gold">New PR</p>
      <p className="font-display text-2xl font-bold">Bench Press</p>
      <p className="mb-6 font-display text-5xl font-extrabold tabular-nums">
        195 <span className="text-lg text-rook-muted">lbs</span>
      </p>
      <Card className="mb-3 w-full text-left">
        <div className="mb-3 flex items-center justify-between">
          <p className="text-sm font-semibold">This Week</p>
          <p className="flex items-center gap-1 text-xs font-semibold text-heat">
            <Flame className="h-3.5 w-3.5" /> 13 days
          </p>
        </div>
        <WeekStrip fillToday={active} />
      </Card>
      <div className="grid w-full grid-cols-2 gap-2 text-left">
        <Card className="!p-3">
          <p className="text-[10px] text-rook-muted">Duration</p>
          <p className="font-mono text-lg font-medium">47:52</p>
        </Card>
        <Card className="!p-3">
          <p className="text-[10px] text-rook-muted">Sets logged</p>
          <p className="font-mono text-lg font-medium">20</p>
        </Card>
      </div>
    </div>
  );
}
