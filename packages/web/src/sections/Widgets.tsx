import type { ReactNode } from 'react';
import { Dumbbell, Flame, Footprints, Zap } from 'lucide-react';
import { Eyebrow, Reveal, SectionTitle } from '../site/ui';
import { WeekStrip } from '../site/screens';

function Widget({ children, wide = false, className = '' }: { children: ReactNode; wide?: boolean; className?: string }) {
  return (
    <div
      className={`rounded-[1.6rem] border border-white/10 bg-rook-canvas/85 p-3 sm:p-4 shadow-[0_20px_50px_-20px_rgba(0,0,0,0.8)] backdrop-blur-xl transition duration-500 hover:-translate-y-1 hover:rotate-[-1deg] ${
        wide ? 'col-span-2' : ''
      } ${className}`}
    >
      {children}
    </div>
  );
}

function AppIcon({ hue }: { hue: string }) {
  return <div className={`aspect-square rounded-[1.1rem] ${hue} opacity-60`} />;
}

/** A home screen with Rook's widgets mixed in among (blurred) app icons. */
export function Widgets() {
  return (
    <section id="widgets" className="relative scroll-mt-16 py-28">
      <div className="mx-auto grid max-w-6xl items-center gap-16 px-4 sm:px-8 lg:grid-cols-[0.9fr_1.1fr]">
        <Reveal>
          <Eyebrow tone="text-mint">Home-screen widgets</Eyebrow>
          <SectionTitle className="mb-6">
            Your streak,
            <br />
            <span className="text-rook-muted">on every unlock.</span>
          </SectionTitle>
          <p className="max-w-md text-lg leading-relaxed text-rook-muted">
            Overview, This Week, Steps and Stats widgets put your progress where you look a hundred times a day. A gentle
            nudge every time you pick up your phone.
          </p>
        </Reveal>

        <Reveal delayMs={120}>
          <div className="relative overflow-hidden rounded-[2.5rem] border border-white/10 bg-[radial-gradient(120%_90%_at_0%_0%,#3a2a7d_0%,#1a1430_45%,#0e0e15_100%)] p-5 sm:p-7">
            <div aria-hidden className="absolute -right-20 -top-20 h-64 w-64 rounded-full bg-heat/20 blur-[80px]" />
            <div className="relative grid grid-cols-4 gap-3 sm:gap-4">
              <Widget wide>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-[10px] font-semibold uppercase tracking-wider text-primary-light">Rook</p>
                    <p className="flex items-center gap-1 font-display text-2xl font-bold">
                      <Flame className="h-5 w-5 text-heat" /> 12
                    </p>
                    <p className="text-[11px] text-rook-muted">day streak</p>
                  </div>
                  <div className="text-right">
                    <p className="font-display text-2xl font-bold">48</p>
                    <p className="text-[11px] text-rook-muted">workouts</p>
                  </div>
                </div>
              </Widget>
              <Widget wide>
                <p className="mb-3 text-[11px] font-semibold text-rook-muted">This Week</p>
                <WeekStrip compact />
              </Widget>

              <AppIcon hue="bg-sky/50" />
              <AppIcon hue="bg-mint/40" />
              <AppIcon hue="bg-white/20" />
              <AppIcon hue="bg-gold/40" />

              <Widget wide>
                <div className="grid h-full grid-cols-3 gap-2 text-center">
                  {[
                    { icon: <Dumbbell className="mx-auto h-4 w-4 text-primary-light" />, v: '48', l: 'Total' },
                    { icon: <Zap className="mx-auto h-4 w-4 text-gold" />, v: '13', l: '30 days' },
                    { icon: <Flame className="mx-auto h-4 w-4 text-heat" />, v: '21', l: 'Best' },
                  ].map((s) => (
                    <div key={s.l} className="flex flex-col justify-center rounded-xl bg-white/[0.04] py-2">
                      {s.icon}
                      <p className="mt-1 font-display text-lg font-bold">{s.v}</p>
                      <p className="text-[10px] text-rook-muted">{s.l}</p>
                    </div>
                  ))}
                </div>
              </Widget>
              <Widget>
                <Footprints className="mb-2 h-4 w-4 text-mint" />
                <p className="font-display text-xl font-bold">8.2k</p>
                <p className="text-[10px] text-rook-muted">steps</p>
              </Widget>
              <Widget>
                <Flame className="mb-2 h-4 w-4 text-heat" />
                <p className="font-display text-xl font-bold">12</p>
                <p className="text-[10px] text-rook-muted">streak</p>
              </Widget>

              <AppIcon hue="bg-heat/40" />
              <AppIcon hue="bg-primary/50" />
              <AppIcon hue="bg-white/15" />
              <AppIcon hue="bg-sky/30" />
            </div>
            <div className="relative mx-auto mt-6 flex w-fit gap-4 rounded-[1.6rem] bg-white/10 p-3 backdrop-blur">
              {['bg-mint/50', 'bg-sky/50', 'bg-primary', 'bg-gold/50'].map((h, i) => (
                <div key={i} className={`flex h-12 w-12 items-center justify-center rounded-[0.9rem] ${h}`}>
                  {h === 'bg-primary' && <span className="font-display text-xl font-black">R</span>}
                </div>
              ))}
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
