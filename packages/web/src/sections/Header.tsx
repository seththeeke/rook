import { useEffect, useState } from 'react';
import { EarlyAccessButton } from '../site/ui';

const NAV = [
  { label: 'How it works', href: '#how-it-works' },
  { label: 'Live Activity', href: '#live-activity' },
  { label: 'Features', href: '#features' },
  { label: 'FAQ', href: '#faq' },
];

/** Transparent over the hero, frosted once the page scrolls. */
export function Header() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-300 ${
        scrolled ? 'border-b border-white/[0.06] bg-rook-ink/75 backdrop-blur-xl' : 'border-b border-transparent'
      }`}
    >
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-8">
        <a href="#top" aria-label="Rook home">
          <img src="/rook-wordmark.png" alt="Rook" className="h-5 w-auto sm:h-6" />
        </a>
        <nav aria-label="Primary" className="hidden items-center gap-8 md:flex">
          {NAV.map((item) => (
            <a key={item.href} href={item.href} className="text-sm font-medium text-rook-muted transition hover:text-white">
              {item.label}
            </a>
          ))}
        </nav>
        <EarlyAccessButton size="md" />
      </div>
    </header>
  );
}
