import { Check, ChevronRight, Flame, Pause, Play, SkipForward, Sparkles, Trophy, Zap, Dumbbell, Timer } from 'lucide-react';
import type { ReactNode } from 'react';

interface LandingPageProps {
  onOpenLogin: () => void;
}

/**
 * Public marketing page for Rook (shown to signed-out visitors on the web).
 * Styled to match the iOS app: gunmetal canvas, white text, purple accent, ROOK wordmark.
 * The phone previews are static illustrations of the app's real screens.
 */
export default function LandingPage({ onOpenLogin }: LandingPageProps) {
  return (
    <div className="min-h-screen bg-rook-canvas text-white antialiased">
      {/* Soft accent glow */}
      <div
        aria-hidden
        className="pointer-events-none fixed -top-40 right-[-10rem] h-[32rem] w-[32rem] rounded-full bg-primary/20 blur-[120px]"
      />

      <header className="sticky top-0 z-50 border-b border-white/5 bg-rook-canvas/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-4">
          <img src="/rook-wordmark.png" alt="Rook" className="h-6 w-auto" />
          <button
            type="button"
            onClick={onOpenLogin}
            className="rounded-xl border border-white/10 bg-rook-elevated px-5 py-2.5 text-sm font-semibold transition hover:bg-white/10"
          >
            Log in
          </button>
        </div>
      </header>

      <main className="relative mx-auto max-w-6xl px-5">
        {/* Hero */}
        <section className="grid items-center gap-12 pb-24 pt-16 md:grid-cols-2 md:pt-24">
          <div className="text-center md:text-left">
            <p className="mb-4 text-xs font-semibold uppercase tracking-[0.35em] text-primary-light">
              Train smarter. Get stronger.
            </p>
            <h1 className="mb-5 text-4xl font-bold tracking-tight sm:text-5xl">
              Build it, start it, <span className="text-primary-light">log every rep.</span>
            </h1>
            <p className="mb-9 text-lg text-rook-muted">
              Rook builds your workout with AI or from your favorites, runs it with a timer on your Lock Screen and
              Dynamic Island, and tracks your streaks and PRs automatically.
            </p>
            <div className="flex flex-col items-center gap-3 sm:flex-row md:justify-start">
              <PrimaryButton onClick={onOpenLogin}>Get started</PrimaryButton>
            </div>
          </div>
          <Phone>
            <DashboardPreview />
          </Phone>
        </section>

        {/* Features */}
        <section className="grid gap-5 pb-24 md:grid-cols-3">
          <Feature icon={<Sparkles className="h-5 w-5" />} title="AI workouts">
            Describe what you want, like “upper body, 45 minutes”, and get a balanced plan from your gym’s equipment.
          </Feature>
          <Feature icon={<Play className="h-5 w-5" />} title="One-tap quick start">
            Repeat a recent workout instantly. Same exercises, sets and reps, no setup.
          </Feature>
          <Feature icon={<Timer className="h-5 w-5" />} title="Live Activity">
            Your session timer and current exercise on the Lock Screen and Dynamic Island, with pause and next.
          </Feature>
        </section>

        {/* Execution */}
        <section className="grid items-center gap-12 pb-24 md:grid-cols-2">
          <div className="order-2 md:order-1">
            <Phone>
              <ExecutionPreview />
            </Phone>
          </div>
          <div className="order-1 text-center md:order-2 md:text-left">
            <SectionEyebrow>Track every rep</SectionEyebrow>
            <h2 className="mb-4 text-3xl font-bold tracking-tight">Log in seconds, mid-set.</h2>
            <p className="text-rook-muted">
              Your last weight is already filled in. Adjust with quick buttons (−5, +5, +10, +25, +50), tap Next, and
              Rook saves as you go, even if you close the app.
            </p>
          </div>
        </section>

        {/* Live Activity */}
        <section className="pb-24 text-center">
          <SectionEyebrow>Always in view</SectionEyebrow>
          <h2 className="mb-4 text-3xl font-bold tracking-tight">Your workout, on your Lock Screen.</h2>
          <p className="mx-auto mb-10 max-w-xl text-rook-muted">
            Keep your phone locked between sets. The timer keeps running, and you can pause or move on without
            opening the app.
          </p>
          <LiveActivityPreview />
        </section>

        {/* CTA */}
        <section className="pb-20 pt-4 text-center">
          <h2 className="mb-4 text-3xl font-bold tracking-tight">Ready to train smarter?</h2>
          <p className="mx-auto mb-8 max-w-md text-rook-muted">Sign in to pick up where you left off.</p>
          <PrimaryButton onClick={onOpenLogin}>Get started</PrimaryButton>
        </section>
      </main>

      <footer className="border-t border-white/5 py-8">
        <div className="mx-auto flex max-w-6xl flex-col items-center gap-3 px-5">
          <img src="/rook-wordmark.png" alt="Rook" className="h-4 w-auto opacity-70" />
          <p className="text-xs text-rook-faint">© {new Date().getFullYear()} Rook. All rights reserved.</p>
        </div>
      </footer>
    </div>
  );
}

// ---------- Building blocks ----------

function PrimaryButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex items-center gap-2 rounded-xl bg-gradient-to-br from-[#8B6CFF] to-[#6A4BE8] px-7 py-3.5 font-semibold shadow-lg shadow-primary/40 transition hover:brightness-110"
    >
      {children}
      <ChevronRight className="h-5 w-5" />
    </button>
  );
}

function SectionEyebrow({ children }: { children: ReactNode }) {
  return <p className="mb-3 text-xs font-semibold uppercase tracking-[0.3em] text-primary-light">{children}</p>;
}

function Feature({ icon, title, children }: { icon: ReactNode; title: string; children: ReactNode }) {
  return (
    <div className="rounded-2xl border border-white/[0.07] bg-rook-surface p-6">
      <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-primary/15 text-primary-light">
        {icon}
      </div>
      <h3 className="mb-2 text-lg font-semibold">{title}</h3>
      <p className="text-sm leading-relaxed text-rook-muted">{children}</p>
    </div>
  );
}

function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-2xl border border-white/[0.07] bg-rook-surface p-4 ${className}`}>{children}</div>;
}

/** An iPhone-shaped frame for the static screen previews. */
function Phone({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-[320px] rounded-[2.75rem] border border-white/10 bg-black p-2.5 shadow-2xl shadow-primary/20">
      <div className="relative overflow-hidden rounded-[2.25rem] bg-rook-canvas">
        <div className="absolute left-1/2 top-2.5 z-10 h-6 w-24 -translate-x-1/2 rounded-full bg-black" />
        <div className="px-4 pb-6 pt-12">{children}</div>
      </div>
    </div>
  );
}

// ---------- Screen previews (illustrations) ----------

function DashboardPreview() {
  const days = [
    { d: 'M', done: true },
    { d: 'T', done: false },
    { d: 'W', done: true },
    { d: 'T', done: false },
    { d: 'F', done: true },
    { d: 'S', done: false, today: true },
    { d: 'S', done: false },
  ];
  return (
    <div className="space-y-3 text-left">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs text-rook-muted">Welcome back,</p>
          <p className="text-xl font-bold">Alex</p>
        </div>
        <div className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-rook-elevated text-sm font-semibold">
          A
        </div>
      </div>
      <Card className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-orange-500/15">
          <Flame className="h-5 w-5 text-orange-400" />
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
      <div className="grid grid-cols-2 gap-2">
        <Card className="!p-3">
          <Dumbbell className="mb-1.5 h-4 w-4 text-primary-light" />
          <p className="text-lg font-bold">48</p>
          <p className="text-[10px] text-rook-muted">Workouts</p>
        </Card>
        <Card className="!p-3">
          <Zap className="mb-1.5 h-4 w-4 text-primary-light" />
          <p className="text-lg font-bold">13</p>
          <p className="text-[10px] text-rook-muted">Last 30 days</p>
        </Card>
      </div>
      <Card>
        <p className="mb-3 text-sm font-semibold">This Week</p>
        <div className="flex justify-between">
          {days.map((day, i) => (
            <div key={i} className="flex flex-col items-center gap-1.5">
              <div
                className={`flex h-7 w-7 items-center justify-center rounded-full border ${
                  day.done
                    ? 'border-transparent bg-primary'
                    : day.today
                      ? 'border-primary bg-primary/10'
                      : 'border-white/[0.07] bg-rook-elevated'
                }`}
              >
                {day.done && <Check className="h-3.5 w-3.5" strokeWidth={3} />}
              </div>
              <span className={`text-[9px] ${day.today ? 'font-bold text-primary-light' : 'text-rook-muted'}`}>
                {day.d}
              </span>
            </div>
          ))}
        </div>
      </Card>
      <Card className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Trophy className="h-4 w-4 text-amber-400" />
          <div>
            <p className="text-[10px] text-rook-muted">Personal Record</p>
            <p className="text-sm font-semibold">Bench Press</p>
          </div>
        </div>
        <p className="text-sm font-bold">225 lbs</p>
      </Card>
    </div>
  );
}

function ExecutionPreview() {
  return (
    <div className="text-center">
      <div className="mb-3 flex items-center justify-between">
        <div className="h-8 w-8" />
        <p className="font-mono text-2xl font-bold tabular-nums">24:18</p>
        <div className="flex h-8 w-8 items-center justify-center rounded-full border border-white/10 bg-rook-elevated">
          <Pause className="h-3.5 w-3.5" />
        </div>
      </div>
      <p className="mb-1.5 text-left text-[10px] text-rook-muted">Exercise 2 of 6</p>
      <div className="mb-6 h-1 overflow-hidden rounded-full bg-rook-elevated">
        <div className="h-full w-1/3 rounded-full bg-primary" />
      </div>
      <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-[#8B6CFF] to-[#6A4BE8] shadow-lg shadow-primary/40">
        <Dumbbell className="h-7 w-7" />
      </div>
      <p className="text-lg font-bold">Barbell Bench Press</p>
      <p className="mb-4 text-xs text-rook-muted">4 sets × 6 reps</p>
      <Card className="mb-4">
        <p className="mb-1 text-[10px] text-rook-muted">Weight (lbs)</p>
        <p className="mb-3 text-4xl font-bold tabular-nums">185</p>
        <div className="grid grid-cols-5 gap-1">
          {['−5', '+5', '+10', '+25', '+50'].map((label) => (
            <div
              key={label}
              className={`rounded-lg border border-white/[0.07] bg-rook-elevated py-1.5 text-[11px] font-semibold ${
                label.startsWith('−') ? 'text-rook-muted' : ''
              }`}
            >
              {label}
            </div>
          ))}
        </div>
      </Card>
      <div className="flex gap-2">
        <div className="flex-1 rounded-xl border border-white/[0.07] bg-rook-elevated py-2.5 text-sm font-semibold">
          Previous
        </div>
        <div className="flex-1 rounded-xl bg-gradient-to-br from-[#8B6CFF] to-[#6A4BE8] py-2.5 text-sm font-semibold">
          Next
        </div>
      </div>
    </div>
  );
}

function LiveActivityPreview() {
  return (
    <div className="mx-auto max-w-md space-y-4">
      {/* Dynamic Island (compact) */}
      <div className="mx-auto flex w-64 items-center justify-between rounded-full bg-black px-4 py-2.5 shadow-xl">
        <Dumbbell className="h-4 w-4 text-primary-light" />
        <span className="font-mono text-sm font-semibold tabular-nums">24:18</span>
      </div>
      {/* Lock Screen */}
      <div className="rounded-3xl border border-white/10 bg-rook-surface/90 p-4 text-left shadow-2xl backdrop-blur">
        <div className="mb-2 flex items-center justify-between text-xs">
          <span className="font-semibold text-primary-light">Garage Gym</span>
          <span className="text-rook-muted">Exercise 2 of 6</span>
        </div>
        <div className="mb-2 flex items-baseline justify-between">
          <span className="font-semibold">Barbell Bench Press</span>
          <span className="font-mono text-2xl font-bold tabular-nums">24:18</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-sm text-white/80">4 sets × 6 reps · 185 lbs</span>
          <div className="flex gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/35">
              <Pause className="h-3.5 w-3.5" />
            </span>
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary">
              <SkipForward className="h-3.5 w-3.5" />
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
