import { useState } from 'react';
import { Plus } from 'lucide-react';
import { CONTACT_EMAIL, CONTACT_HREF } from '../site/config';
import { EarlyAccessButton, Eyebrow, Reveal, SectionTitle } from '../site/ui';

const FAQS = [
  {
    q: 'How do I get Rook?',
    a: 'Rook is in early access on iPhone. Tap “Get early access”, send us a note, and we’ll get you set up with an invite.',
  },
  {
    q: 'What do I need?',
    a: 'An iPhone running iOS 17 or later. Live Activities and the Dynamic Island light up on the iPhones that support them.',
  },
  {
    q: 'Do I have to use the AI builder?',
    a: 'Not at all. Pick exercises yourself, or repeat a recent workout in one tap. The AI is there when you want a fresh plan fast.',
  },
  {
    q: 'Does it work if I close the app mid-workout?',
    a: 'Yes. Rook saves as you go, and your session keeps running on the Lock Screen and Dynamic Island while your phone is locked.',
  },
  {
    q: 'Is there a web version?',
    a: 'Rook is built for the phone in your pocket at the gym, so it lives on iPhone. This site is just here to say hello.',
  },
];

export function Faq() {
  const [open, setOpen] = useState<number | null>(0);
  return (
    <section id="faq" className="scroll-mt-16 py-28">
      <div className="mx-auto grid max-w-6xl gap-12 px-4 sm:px-8 lg:grid-cols-[0.8fr_1.2fr]">
        <Reveal>
          <Eyebrow>FAQ</Eyebrow>
          <SectionTitle>
            Good
            <br />
            questions.
          </SectionTitle>
          <p className="mt-6 text-rook-muted">
            Something else? Email{' '}
            <a href={CONTACT_HREF} className="text-primary-light underline-offset-4 hover:underline">
              {CONTACT_EMAIL}
            </a>
            .
          </p>
        </Reveal>
        <Reveal delayMs={100}>
          <ul className="divide-y divide-white/[0.08] border-y border-white/[0.08]">
            {FAQS.map((f, i) => {
              const isOpen = open === i;
              return (
                <li key={f.q}>
                  <button
                    type="button"
                    aria-expanded={isOpen}
                    onClick={() => setOpen(isOpen ? null : i)}
                    className="flex w-full items-center justify-between gap-6 py-6 text-left"
                  >
                    <span className="font-display text-lg font-semibold sm:text-xl">{f.q}</span>
                    <Plus
                      className={`h-5 w-5 shrink-0 text-primary-light transition-transform duration-300 ${isOpen ? 'rotate-45' : ''}`}
                    />
                  </button>
                  <div
                    className={`grid transition-all duration-300 ease-out ${isOpen ? 'grid-rows-[1fr] pb-6 opacity-100' : 'grid-rows-[0fr] opacity-0'}`}
                  >
                    <p className="overflow-hidden leading-relaxed text-rook-muted">{f.a}</p>
                  </div>
                </li>
              );
            })}
          </ul>
        </Reveal>
      </div>
    </section>
  );
}

export function FinalCta() {
  return (
    <section className="relative overflow-hidden px-4 pb-28 pt-12 sm:px-8">
      <Reveal>
        <div className="relative mx-auto max-w-6xl overflow-hidden rounded-[2.5rem] border border-white/10 bg-gradient-to-br from-[#2b1f6e] via-[#1a1530] to-rook-ink px-6 py-20 text-center sm:px-16 sm:py-28">
          <div aria-hidden className="absolute -left-24 -top-24 h-80 w-80 rounded-full bg-primary/40 blur-[100px]" />
          <div aria-hidden className="absolute -bottom-32 -right-16 h-80 w-80 rounded-full bg-heat/25 blur-[110px]" />
          <div aria-hidden className="rk-grid-lines absolute inset-0 [mask-image:radial-gradient(ellipse_at_center,#000,transparent_70%)]" />
          <div className="relative">
            <p className="mb-5 font-mono text-xs uppercase tracking-[0.3em] text-primary-light">Your next PR is waiting</p>
            <h2 className="mx-auto mb-6 max-w-3xl font-display text-5xl font-black leading-[0.95] tracking-tight sm:text-7xl">
              Stop planning.
              <br />
              <span className="rk-gradient-text">Start lifting.</span>
            </h2>
            <p className="mx-auto mb-10 max-w-md text-lg text-white/70">
              Rook is in early access. Reach out and we’ll get you in.
            </p>
            <EarlyAccessButton />
          </div>
        </div>
      </Reveal>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="border-t border-white/[0.06] bg-black/30">
      <div className="mx-auto grid max-w-6xl gap-10 px-4 py-14 sm:px-8 md:grid-cols-[1.4fr_1fr_1fr]">
        <div>
          <img src="/rook-wordmark.png" alt="Rook" className="mb-4 h-6 w-auto" />
          <p className="max-w-xs text-sm text-rook-muted">
            The workout app that builds it, runs it and keeps score, so you can just lift.
          </p>
        </div>
        <div>
          <h3 className="mb-3 text-xs font-bold uppercase tracking-[0.2em] text-rook-faint">Explore</h3>
          <ul className="space-y-2 text-sm">
            {[
              ['How it works', '#how-it-works'],
              ['Live Activity', '#live-activity'],
              ['Features', '#features'],
              ['Widgets', '#widgets'],
            ].map(([label, href]) => (
              <li key={href}>
                <a href={href} className="text-rook-muted transition hover:text-white">
                  {label}
                </a>
              </li>
            ))}
          </ul>
        </div>
        <div>
          <h3 className="mb-3 text-xs font-bold uppercase tracking-[0.2em] text-rook-faint">Contact</h3>
          <a href={CONTACT_HREF} className="text-sm text-primary-light hover:underline">
            {CONTACT_EMAIL}
          </a>
          <p className="mt-2 text-xs text-rook-faint">We usually reply within a couple of days.</p>
        </div>
      </div>
      <div className="border-t border-white/[0.06]">
        <div className="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-6 text-xs text-rook-faint sm:flex-row sm:justify-between sm:px-8">
          <p>© {new Date().getFullYear()} Rook. All rights reserved.</p>
          <p>iPhone, Dynamic Island and Live Activities are trademarks of Apple Inc.</p>
        </div>
      </div>
    </footer>
  );
}
