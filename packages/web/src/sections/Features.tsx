import { useEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react';
import { Flame, Footprints, History, Sparkles, ThermometerSun, Trophy, Warehouse } from 'lucide-react';
import { Eyebrow, Reveal, SectionTitle } from '../site/ui';
import { WeekStrip } from '../site/screens';
import { useCountUp, useInView, useReducedMotion, useTypewriter } from '../site/hooks';

/** A bento card with a soft spotlight that follows the cursor. */
function Tile({
  children,
  className = '',
  glow = 'rgba(124,92,250,0.18)',
}: {
  children: ReactNode;
  className?: string;
  glow?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const onMove = (e: MouseEvent<HTMLDivElement>) => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty('--x', `${e.clientX - r.left}px`);
    el.style.setProperty('--y', `${e.clientY - r.top}px`);
  };
  return (
    <div
      ref={ref}
      onMouseMove={onMove}
      className={`group relative overflow-hidden rounded-3xl border border-white/[0.07] bg-rook-surface/70 p-7 backdrop-blur transition-colors hover:border-white/15 ${className}`}
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 group-hover:opacity-100"
        style={{ background: `radial-gradient(420px circle at var(--x) var(--y), ${glow}, transparent 60%)` }}
      />
      <div className="relative h-full">{children}</div>
    </div>
  );
}

function TileHead({ icon, title, children }: { icon: ReactNode; title: string; children: ReactNode }) {
  return (
    <div className="mb-6">
      <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-white/[0.06]">{icon}</div>
      <h3 className="mb-2 font-display text-2xl font-bold">{title}</h3>
      <p className="max-w-sm text-sm leading-relaxed text-rook-muted">{children}</p>
    </div>
  );
}

const PROMPTS = ['Legs, no barbell, 30 minutes', 'Full body for a hotel gym', 'Heavy push day, 5×5', 'Back and biceps, 40 minutes'];

function PromptCycler() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, 0.4);
  const reduced = useReducedMotion();
  const [i, setI] = useState(0);
  const text = useTypewriter(PROMPTS[i], inView, 50);
  useEffect(() => {
    if (reduced || text.length < PROMPTS[i].length) return;
    const id = window.setTimeout(() => setI((n) => (n + 1) % PROMPTS.length), 1800);
    return () => window.clearTimeout(id);
  }, [text, i, reduced]);
  return (
    <div ref={ref} className="rounded-2xl border border-primary/40 bg-rook-ink/70 p-4 shadow-[0_0_40px_-10px_rgba(124,92,250,0.6)]">
      <div className="mb-2 flex items-center gap-2 text-xs text-primary-light">
        <Sparkles className="h-3.5 w-3.5" /> What do you want to train?
      </div>
      <p className="min-h-[1.75rem] font-display text-lg font-semibold sm:text-xl">
        <span className="rk-caret">{text}</span>
      </p>
    </div>
  );
}

const PR_BARS = [135, 155, 165, 175, 185, 195, 225];

function PrChart() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, 0.4);
  const top = useCountUp(225, inView, 1800);
  return (
    <div ref={ref}>
      <p className="mb-3 font-display text-4xl font-extrabold tabular-nums">
        {Math.round(top)} <span className="text-base font-semibold text-rook-muted">lb bench</span>
      </p>
      <div className="flex h-24 items-end gap-1.5">
        {PR_BARS.map((v, idx) => (
          <div
            key={idx}
            className={`flex-1 rounded-t-md transition-all duration-700 ease-out ${idx === PR_BARS.length - 1 ? 'bg-gradient-to-t from-heat to-gold' : 'bg-white/15'}`}
            style={{ height: inView ? `${(v / 225) * 100}%` : '6%', transitionDelay: `${idx * 90}ms` }}
          />
        ))}
      </div>
    </div>
  );
}

function StepsRing() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, 0.4);
  const steps = useCountUp(8214, inView, 1800);
  const pct = steps / 10000;
  const C = 2 * Math.PI * 42;
  return (
    <div ref={ref} className="flex items-center gap-5">
      <svg viewBox="0 0 100 100" className="h-24 w-24 -rotate-90">
        <circle cx="50" cy="50" r="42" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="10" />
        <circle
          cx="50"
          cy="50"
          r="42"
          fill="none"
          stroke="#3EE6A8"
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray={C}
          strokeDashoffset={C * (1 - pct)}
        />
      </svg>
      <div>
        <p className="font-display text-3xl font-extrabold tabular-nums">{Math.round(steps).toLocaleString()}</p>
        <p className="text-xs text-rook-muted">steps today</p>
      </div>
    </div>
  );
}

const EQUIPMENT = ['Barbell', 'Dumbbells', 'Cable', 'Pull-up bar', 'Bench', 'Kettlebell', 'Bands', 'Smith machine'];

export function Features() {
  return (
    <section id="features" className="relative scroll-mt-16 py-28">
      <div className="mx-auto max-w-6xl px-4 sm:px-8">
        <Reveal className="mb-14 max-w-3xl">
          <Eyebrow>Everything else</Eyebrow>
          <SectionTitle>
            Small details.
            <br />
            <span className="text-rook-muted">Serious progress.</span>
          </SectionTitle>
        </Reveal>

        <div className="grid gap-4 md:grid-cols-6">
          <Reveal className="md:col-span-4">
            <Tile className="rk-grid-lines h-full">
              <TileHead icon={<Sparkles className="h-5 w-5 text-primary-light" />} title="An AI coach that knows your gym">
                Describe the session you’re after in plain words. Rook picks exercises, sets and reps that fit your time and
                your equipment.
              </TileHead>
              <PromptCycler />
            </Tile>
          </Reveal>
          <Reveal className="md:col-span-2" delayMs={80}>
            <Tile className="h-full" glow="rgba(92,200,255,0.18)">
              <TileHead icon={<History className="h-5 w-5 text-sky" />} title="One-tap repeat">
                Liked Tuesday’s push day? Start it again with the same exercises, sets and reps. Zero setup.
              </TileHead>
              <div className="flex items-center justify-between rounded-2xl border border-white/[0.07] bg-rook-ink/60 p-3">
                <div>
                  <p className="text-sm font-semibold">Push Day</p>
                  <p className="text-xs text-rook-muted">Tue · 6 exercises</p>
                </div>
                <span className="rounded-full bg-sky/15 px-3 py-1.5 text-xs font-semibold text-sky">Start</span>
              </div>
            </Tile>
          </Reveal>

          <Reveal className="md:col-span-2">
            <Tile className="h-full" glow="rgba(255,122,69,0.18)">
              <TileHead icon={<Flame className="h-5 w-5 text-heat" />} title="Streaks that stick">
                Your week fills in as you train. Miss a day and you’ll feel it.
              </TileHead>
              <WeekStrip />
            </Tile>
          </Reveal>
          <Reveal className="md:col-span-2" delayMs={80}>
            <Tile className="h-full" glow="rgba(255,201,77,0.18)">
              <TileHead icon={<Trophy className="h-5 w-5 text-gold" />} title="PRs, caught automatically">
                Every lift is tracked, so new bests are flagged the moment you set them.
              </TileHead>
              <PrChart />
            </Tile>
          </Reveal>
          <Reveal className="md:col-span-2" delayMs={160}>
            <Tile className="h-full" glow="rgba(62,230,168,0.16)">
              <TileHead icon={<Footprints className="h-5 w-5 text-mint" />} title="Steps on the dashboard">
                Today’s step count sits right beside your training stats.
              </TileHead>
              <StepsRing />
            </Tile>
          </Reveal>

          <Reveal className="md:col-span-3">
            <Tile className="h-full bg-gradient-to-br from-heat/[0.12] via-rook-surface/70 to-rook-surface/70" glow="rgba(255,122,69,0.22)">
              <TileHead icon={<ThermometerSun className="h-5 w-5 text-heat" />} title="Recovery counts too">
                Log sauna sessions right next to your lifts, so recovery shows up in your week and keeps your streak alive.
              </TileHead>
              <div className="flex items-end gap-2" aria-hidden>
                {[0, 1, 2, 3, 4].map((n) => (
                  <span
                    key={n}
                    className="h-10 w-1.5 rounded-full bg-gradient-to-t from-heat/0 via-heat/60 to-gold/80 animate-[rk-float_2.2s_ease-in-out_infinite]"
                    style={{ animationDelay: `${n * 0.25}s` }}
                  />
                ))}
                <span className="ml-3 font-display text-2xl font-bold">
                  Sauna <span className="text-base font-medium text-rook-muted">· 20 min</span>
                </span>
              </div>
            </Tile>
          </Reveal>
          <Reveal className="md:col-span-3" delayMs={80}>
            <Tile className="h-full">
              <TileHead icon={<Warehouse className="h-5 w-5 text-primary-light" />} title="Built around your gym">
                Garage, hotel or big-box: Rook plans around the equipment you actually have, so every workout fits the room you’re in.
              </TileHead>
              <div className="flex flex-wrap gap-2">
                {EQUIPMENT.map((e) => (
                  <span key={e} className="rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 text-xs font-medium text-white/80">
                    {e}
                  </span>
                ))}
              </div>
            </Tile>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
