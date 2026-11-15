import { useEffect, useRef } from 'react';
import { useReducedMotion } from '../site/hooks';

const SPACING = 30;
const BEAT_MS = 860; // ~70 bpm
const WAVE_SPEED = 0.42; // px per ms
const WAVE_LIFE_MS = 2600;
const ECG_PERIOD = 300; // px between heartbeats on the trace
const SWEEP_SPEED = ECG_PERIOD / BEAT_MS; // the trace head crosses one spike per beat
const SPIKE_U = 0.33; // where the tall spike sits within a period

type Wave = { x: number; y: number; start: number; gold: boolean };

/** One heartbeat of a monitor trace, as a vertical offset for x within a period (0..1). */
function ecg(u: number): number {
  const bump = (c: number, w: number, h: number) => h * Math.exp(-((u - c) ** 2) / (2 * w * w));
  return bump(0.18, 0.03, -0.1) + bump(0.3, 0.008, 0.18) + bump(0.33, 0.01, -1) + bump(0.36, 0.009, 0.35) + bump(0.58, 0.05, -0.22);
}

/*
 * The hero backdrop: a field of dots with a heart-rate monitor trace sweeping across it.
 * Every beat sends a ripple through the dots (now and then a gold one, a "PR").
 * Draws a single still frame for reduced motion, and pauses off-screen.
 */
export function PulseCanvas() {
  const ref = useRef<HTMLCanvasElement>(null);
  const reduced = useReducedMotion();

  useEffect(() => {
    const canvas = ref.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;

    let width = 0;
    let height = 0;
    let frame = 0;
    let visible = true;
    let lastBeat = Number.NaN;
    let beatCount = 0;
    const waves: Wave[] = [];
    const origin = performance.now();

    const resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = canvas.clientWidth;
      height = canvas.clientHeight;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    const draw = (now: number) => {
      const t = now - origin;
      ctx.clearRect(0, 0, width, height);

      const traceY = height * 0.88;
      const amp = Math.min(90, height * 0.1);
      const sweepX = (t * SWEEP_SPEED) % (width + 200);

      // Spawn a ripple each time the trace head crosses a spike.
      const beat = Math.floor(sweepX / ECG_PERIOD - SPIKE_U);
      if (beat !== lastBeat) {
        lastBeat = beat;
        const spikeX = (beat + SPIKE_U) * ECG_PERIOD;
        if (spikeX >= 0) {
          beatCount += 1;
          waves.push({ x: spikeX, y: traceY - amp, start: t, gold: beatCount % 7 === 0 });
        }
      }
      while (waves.length && t - waves[0].start > WAVE_LIFE_MS) waves.shift();

      // Dot field.
      for (let gx = SPACING / 2; gx < width; gx += SPACING) {
        for (let gy = SPACING / 2; gy < height; gy += SPACING) {
          let glow = 0;
          let gold = 0;
          for (const w of waves) {
            const age = t - w.start;
            const dist = Math.hypot(gx - w.x, gy - w.y);
            const ring = dist - age * WAVE_SPEED;
            const fade = 1 - age / WAVE_LIFE_MS;
            const g = Math.exp(-(ring * ring) / 900) * fade * fade;
            glow += g;
            if (w.gold) gold += g;
          }
          glow = Math.min(1, glow);
          const r = 1 + glow * 1.8;
          if (gold > 0.15) ctx.fillStyle = `rgba(255, 201, 77, ${0.12 + Math.min(1, gold) * 0.8})`;
          else ctx.fillStyle = `rgba(159, 134, 255, ${0.1 + glow * 0.75})`;
          ctx.beginPath();
          ctx.arc(gx, gy, r, 0, Math.PI * 2);
          ctx.fill();
        }
      }

      // Monitor trace: brightest at the head, fading out behind it.
      const tail = 520;
      const startX = Math.max(0, sweepX - tail);
      const grad = ctx.createLinearGradient(startX, 0, sweepX, 0);
      grad.addColorStop(0, 'rgba(124, 92, 250, 0)');
      grad.addColorStop(0.7, 'rgba(124, 92, 250, 0.55)');
      grad.addColorStop(1, 'rgba(214, 204, 255, 1)');
      ctx.strokeStyle = grad;
      ctx.lineWidth = 2.2;
      ctx.lineJoin = 'round';
      ctx.shadowColor = 'rgba(124, 92, 250, 0.9)';
      ctx.shadowBlur = 14;
      ctx.beginPath();
      for (let x = startX; x <= sweepX; x += 2) {
        const u = (x / ECG_PERIOD) % 1;
        const y = traceY + ecg(u) * amp;
        if (x === startX) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
      ctx.shadowBlur = 0;

      // Head dot.
      ctx.fillStyle = '#fff';
      ctx.shadowColor = 'rgba(214, 204, 255, 1)';
      ctx.shadowBlur = 18;
      ctx.beginPath();
      ctx.arc(sweepX, traceY + ecg((sweepX / ECG_PERIOD) % 1) * amp, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowBlur = 0;
    };

    const loop = (now: number) => {
      if (visible && !document.hidden) draw(now);
      frame = requestAnimationFrame(loop);
    };

    resize();
    const ro = new ResizeObserver(() => {
      resize();
      if (reduced) draw(origin + 2400);
    });
    ro.observe(canvas);
    const io = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
    });
    io.observe(canvas);

    if (reduced) draw(origin + 2400);
    else frame = requestAnimationFrame(loop);

    return () => {
      cancelAnimationFrame(frame);
      ro.disconnect();
      io.disconnect();
    };
  }, [reduced]);

  return <canvas ref={ref} aria-hidden className="absolute inset-0 h-full w-full" />;
}
