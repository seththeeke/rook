import { useRef, type ReactNode } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Eyebrow, Phone, Reveal, SectionTitle } from '../site/ui';
import { BuilderScreen, ExecutionScreen, ProgressScreen } from '../site/screens';
import { LockScreenScene } from './LiveActivity';
import { useInView, useStickyProgress } from '../site/hooks';

type Step = {
  id: string;
  kicker: string;
  title: string;
  body: string;
  screen: (active: boolean) => ReactNode;
};

const STEPS: Step[] = [
  {
    id: 'build',
    kicker: '01 · Build',
    title: 'Say what you want. Get a real plan.',
    body: 'Type “upper body, 45 minutes” and Rook builds a balanced session from the equipment at your gym. Or one-tap a recent workout and go.',
    screen: (a) => <BuilderScreen active={a} />,
  },
  {
    id: 'start',
    kicker: '02 · Start',
    title: 'Lock your phone. Keep your place.',
    body: 'Your timer and current exercise live on the Lock Screen and Dynamic Island. Pause or move to the next lift without opening the app.',
    screen: (a) => <LockScreenScene active={a} />,
  },
  {
    id: 'log',
    kicker: '03 · Log',
    title: 'Log mid-set in a single tap.',
    body: 'Last time’s weight is already filled in. Nudge it with −5, +5, +10, +25 or +50 and hit Next. Rook saves as you go, even if the app closes.',
    screen: (a) => <ExecutionScreen active={a} />,
  },
  {
    id: 'grow',
    kicker: '04 · Level up',
    title: 'Streaks and PRs that keep score for you.',
    body: 'Finish and your streak, week and personal records update on their own. No spreadsheets, no math, just the next reason to come back.',
    screen: (a) => <ProgressScreen active={a} />,
  },
];

const SCROLL_PER_STEP_VH = 70;

function StepCopy({ step, active }: { step: Step; active?: boolean }) {
  return (
    <div className={`transition-opacity duration-500 ${active === false ? 'opacity-30' : 'opacity-100'}`}>
      <p className="mb-2 font-mono text-xs font-medium uppercase tracking-[0.25em] text-primary-light">{step.kicker}</p>
      <h3 className="mb-3 font-display text-2xl font-bold leading-tight sm:text-3xl">{step.title}</h3>
      <p className="max-w-md leading-relaxed text-rook-muted">{step.body}</p>
    </div>
  );
}

/** Desktop: the section pins a phone while scrolling walks through the four steps. */
function PinnedStory() {
  const ref = useRef<HTMLDivElement>(null);
  const progress = useStickyProgress(ref);
  const count = STEPS.length;
  const active = Math.min(count - 1, Math.floor(progress * count));

  return (
    <div ref={ref} className="relative hidden lg:block" style={{ height: `calc(${count * SCROLL_PER_STEP_VH}vh + 100vh)` }}>
      <div className="sticky top-0 flex h-screen items-center">
        <div className="mx-auto grid w-full max-w-6xl grid-cols-[1fr_auto] items-center gap-16 px-8">
          <div>
            <ol aria-label="Steps" className="mb-10 grid grid-cols-4 gap-2">
              {STEPS.map((s, i) => {
                const fill = Math.min(1, Math.max(0, progress * count - i));
                return (
                  <li key={s.id} aria-current={i === active ? 'step' : undefined} className="flex flex-col gap-2">
                    <span className="h-1 overflow-hidden rounded-full bg-white/10">
                      <span
                        className="block h-full origin-left rounded-full bg-gradient-to-r from-primary to-[#ff9a6b]"
                        style={{ transform: `scaleX(${fill})` }}
                      />
                    </span>
                    <span className={`text-xs font-semibold transition-colors ${i === active ? 'text-white' : 'text-rook-faint'}`}>
                      {s.kicker.split(' · ')[1]}
                    </span>
                  </li>
                );
              })}
            </ol>
            <div className="relative min-h-[220px]">
              <AnimatePresence mode="wait">
                <motion.div
                  key={STEPS[active].id}
                  initial={{ opacity: 0, y: 24, filter: 'blur(8px)' }}
                  animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
                  exit={{ opacity: 0, y: -24, filter: 'blur(8px)' }}
                  transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
                >
                  <p aria-hidden className="pointer-events-none absolute -right-2 -top-16 select-none font-display text-[11rem] font-black leading-none text-white/[0.03]">
                    {String(active + 1).padStart(2, '0')}
                  </p>
                  <StepCopy step={STEPS[active]} />
                </motion.div>
              </AnimatePresence>
            </div>
          </div>
          <div className="relative origin-center [@media(max-height:860px)]:scale-[0.85] [@media(max-height:740px)]:scale-75">
            <div aria-hidden className="absolute -inset-12 rounded-full bg-primary/20 blur-[90px]" />
            <Phone>
              <AnimatePresence mode="wait">
                <motion.div
                  key={STEPS[active].id}
                  className="h-full"
                  initial={{ opacity: 0, scale: 0.96 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 1.03 }}
                  transition={{ duration: 0.35 }}
                >
                  {STEPS[active].screen(true)}
                </motion.div>
              </AnimatePresence>
            </Phone>
          </div>
        </div>
      </div>
    </div>
  );
}

function StackedStep({ step }: { step: Step }) {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, 0.35);
  return (
    <div ref={ref}>
      <Reveal className="grid items-center gap-10 md:grid-cols-2">
        <StepCopy step={step} />
        <Phone>{step.screen(inView)}</Phone>
      </Reveal>
    </div>
  );
}

/** Phones and tablets: the same story, stacked. Each screen starts when it scrolls in. */
function StackedStory() {
  return (
    <div className="mx-auto max-w-6xl space-y-24 px-4 pb-8 sm:px-8 lg:hidden">
      {STEPS.map((s) => (
        <StackedStep key={s.id} step={s} />
      ))}
    </div>
  );
}

export function HowItWorks() {
  return (
    <section id="how-it-works" className="relative scroll-mt-16 pt-24">
      <div className="mx-auto mb-16 max-w-6xl px-4 sm:px-8 lg:mb-0">
        <Reveal>
          <Eyebrow>How it works</Eyebrow>
          <SectionTitle>
            From couch to cooldown,
            <br />
            <span className="text-rook-muted">in four moves.</span>
          </SectionTitle>
        </Reveal>
      </div>
      <PinnedStory />
      <StackedStory />
    </section>
  );
}
