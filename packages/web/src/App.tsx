import { Header } from './sections/Header';
import { Hero } from './sections/Hero';
import { LiftMarquee, StatsBand } from './sections/Marquee';
import { HowItWorks } from './sections/HowItWorks';
import { LiveActivity } from './sections/LiveActivity';
import { Features } from './sections/Features';
import { Widgets } from './sections/Widgets';
import { Faq, FinalCta, Footer } from './sections/Closing';

/**
 * The Rook marketing site. Marketing only: there is no sign-in or app here. Rook itself is the
 * native iPhone app in ios-app/; every call to action emails us for early access.
 */
export default function App() {
  return (
    <div id="top">
      <div className="rk-page-bg" aria-hidden />
      <Header />
      <main>
        <Hero />
        <LiftMarquee />
        <StatsBand />
        <HowItWorks />
        <LiveActivity />
        <Features />
        <Widgets />
        <Faq />
        <FinalCta />
      </main>
      <Footer />
    </div>
  );
}
