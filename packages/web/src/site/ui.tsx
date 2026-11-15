import { useRef, type ReactNode } from 'react';
import { ArrowRight } from 'lucide-react';
import { CONTACT_HREF } from './config';
import { useInView } from './hooks';

/** Fades, lifts and un-blurs its children the first time they scroll into view. */
export function Reveal({
  children,
  delayMs = 0,
  className = '',
}: {
  children: ReactNode;
  delayMs?: number;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, 0.15);
  return (
    <div
      ref={ref}
      style={{ transitionDelay: `${delayMs}ms` }}
      className={`transition-all duration-1000 ease-[cubic-bezier(0.2,0.8,0.2,1)] ${
        inView ? 'translate-y-0 opacity-100 blur-0' : 'translate-y-10 opacity-0 blur-sm'
      } ${className}`}
    >
      {children}
    </div>
  );
}

export function Eyebrow({ children, tone = 'text-primary-light' }: { children: ReactNode; tone?: string }) {
  return <p className={`mb-3 text-xs font-semibold uppercase tracking-[0.32em] ${tone}`}>{children}</p>;
}

export function SectionTitle({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <h2 className={`font-display text-4xl font-extrabold leading-[1.02] tracking-tight sm:text-5xl lg:text-6xl ${className}`}>
      {children}
    </h2>
  );
}

/** The one call to action: an email asking for early access, with a spinning gradient rim. */
export function EarlyAccessButton({ size = 'lg' }: { size?: 'md' | 'lg' }) {
  const pad = size === 'lg' ? 'px-7 py-4 text-base' : 'px-5 py-2.5 text-sm';
  return (
    <a href={CONTACT_HREF} className="rk-rim group inline-flex rounded-full font-semibold text-white">
      <span className={`inline-flex items-center gap-2 rounded-full bg-rook-ink transition group-hover:bg-[#1a1726] ${pad}`}>
        Get early access
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
      </span>
    </a>
  );
}

/** An iPhone-shaped frame for the static screen illustrations. */
export function Phone({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={`relative mx-auto w-[300px] rounded-[3rem] border border-white/15 bg-gradient-to-b from-[#2a2a33] to-[#121218] p-[9px] shadow-[0_40px_120px_-20px_rgba(124,92,250,0.45)] ${className}`}
    >
      <div className="relative h-[610px] overflow-hidden rounded-[2.5rem] bg-rook-canvas">
        <div className="absolute left-1/2 top-3 z-20 h-[26px] w-[92px] -translate-x-1/2 rounded-full bg-black" />
        <div className="absolute inset-x-0 top-0 z-10 flex justify-between px-7 pt-3.5 text-[11px] font-semibold">
          <span>9:41</span>
          <span className="flex items-center gap-1">
            <span className="h-2 w-3 rounded-[2px] bg-white/90" />
          </span>
        </div>
        <div className="h-full px-4 pb-6 pt-14">{children}</div>
      </div>
    </div>
  );
}

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-2xl border border-white/[0.07] bg-rook-surface p-4 ${className}`}>{children}</div>;
}
