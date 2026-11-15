import type { GiftId } from '../../shared/catalog';

/** Deterministic PRNG: both partners get the same seed from the server, so both see the same show. */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  /** gravity, px/s² (in 1000-wide units) */
  g: number;
  size: number;
  rot: number;
  vr: number;
  born: number;
  life: number;
  emoji?: string;
  color?: string;
  kind: 'emoji' | 'dot' | 'petal' | 'streak' | 'rocket';
  sway?: number;
  swayPhase?: number;
  /** Rockets burst into this many sparks when their life ends. */
  burst?: { colors: string[]; count: number };
  bounce?: boolean;
}

interface Show {
  started: number;
  particles: Particle[];
  rand: () => number;
  /** Extra hook for choreographed gifts (champagne clink). */
  script?: (t: number, show: Show, w: number, h: number) => void;
  state: Record<string, unknown>;
  duration: number;
}

const FIREWORK_PALETTES = [
  ['#ff6f91', '#ffc2d1', '#fff1f5'],
  ['#ffb86b', '#ffe3b3', '#fff8ec'],
  ['#8fd3ff', '#d6f0ff', '#ffffff'],
  ['#c49bff', '#eadbff', '#ffffff'],
  ['#7dffb3', '#d8ffe9', '#ffffff'],
];

/**
 * Renders gift animations on a full-viewport canvas. Coordinates are in a 1000 × (1000·h/w)
 * world so the choreography looks the same on a laptop and a 4K monitor.
 */
export class GiftEngine {
  private ctx: CanvasRenderingContext2D;
  private shows: Show[] = [];
  private raf = 0;
  private lastFrame = 0;
  private dpr = 1;
  private w = 0;
  private h = 0;
  private readonly reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.ctx = canvas.getContext('2d')!;
    this.resize();
  }

  resize(): void {
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = this.canvas.clientWidth || window.innerWidth;
    this.h = this.canvas.clientHeight || window.innerHeight;
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
  }

  play(gift: GiftId, seed: number): void {
    const rand = mulberry32(seed);
    const show: Show = { started: performance.now(), particles: [], rand, state: {}, duration: 4500 };
    const W = 1000;
    const H = (1000 * this.h) / Math.max(1, this.w);
    const now = show.started;
    const add = (p: Omit<Particle, 'born' | 'rot' | 'vr'> & Partial<Pick<Particle, 'rot' | 'vr' | 'born'>>) =>
      show.particles.push({ rot: 0, vr: 0, born: now, ...p });
    const n = (count: number) => (this.reduceMotion ? Math.ceil(count / 3) : count);

    switch (gift) {
      case 'hearts': {
        const hearts = ['💕', '💖', '💗', '❤️', '💓'];
        for (let i = 0; i < n(28); i++) {
          add({
            kind: 'emoji',
            emoji: hearts[Math.floor(rand() * hearts.length)],
            x: 80 + rand() * 840,
            y: H + 40 + rand() * 120,
            vx: 0,
            vy: -(140 + rand() * 160),
            g: 0,
            size: 26 + rand() * 34,
            life: 3200 + rand() * 1200,
            sway: 18 + rand() * 30,
            swayPhase: rand() * Math.PI * 2,
            born: now + rand() * 900,
          });
        }
        break;
      }
      case 'popcorn': {
        const fromLeft = rand() > 0.5;
        for (let i = 0; i < n(34); i++) {
          add({
            kind: 'emoji',
            emoji: i % 9 === 0 ? '🍿' : '🌽',
            x: fromLeft ? -20 : W + 20,
            y: H * (0.55 + rand() * 0.25),
            vx: (fromLeft ? 1 : -1) * (260 + rand() * 320),
            vy: -(380 + rand() * 260),
            g: 620,
            size: i % 9 === 0 ? 46 : 20 + rand() * 12,
            rot: rand() * 6,
            vr: (rand() - 0.5) * 10,
            life: 3600,
            bounce: true,
            born: now + rand() * 700,
          });
        }
        // the white puffs: drawn as soft dots
        for (let i = 0; i < n(40); i++) {
          add({
            kind: 'dot',
            color: rand() > 0.3 ? '#fff6e0' : '#ffd36b',
            x: fromLeft ? -10 : W + 10,
            y: H * (0.55 + rand() * 0.25),
            vx: (fromLeft ? 1 : -1) * (240 + rand() * 360),
            vy: -(360 + rand() * 300),
            g: 620,
            size: 6 + rand() * 6,
            life: 3400,
            bounce: true,
            born: now + rand() * 800,
          });
        }
        break;
      }
      case 'kiss': {
        add({ kind: 'emoji', emoji: '💋', x: W / 2, y: H / 2, vx: 0, vy: 0, g: 0, size: 160, life: 2600 });
        show.script = (t, s) => {
          if (t > 900 && !s.state.burst) {
            s.state.burst = true;
            for (let i = 0; i < n(26); i++) {
              const a = (i / 26) * Math.PI * 2;
              const speed = 220 + s.rand() * 200;
              s.particles.push({
                kind: 'emoji',
                emoji: s.rand() > 0.5 ? '💗' : '💕',
                x: W / 2,
                y: H / 2,
                vx: Math.cos(a) * speed,
                vy: Math.sin(a) * speed,
                g: 60,
                size: 22 + s.rand() * 18,
                rot: 0,
                vr: 0,
                born: performance.now(),
                life: 2200,
              });
            }
          }
        };
        break;
      }
      case 'champagne': {
        // Two glasses glide in from each side, clink in the middle, then fizz.
        show.state.clinked = false;
        add({ kind: 'emoji', emoji: '🥂', x: -80, y: H * 0.52, vx: 0, vy: 0, g: 0, size: 120, life: 3600, rot: 0.35 });
        add({ kind: 'emoji', emoji: '🥂', x: W + 80, y: H * 0.52, vx: 0, vy: 0, g: 0, size: 120, life: 3600, rot: -0.35 });
        show.script = (t, s) => {
          const [left, right] = s.particles;
          if (!left || !right) return;
          const p = Math.min(1, t / 900);
          const ease = 1 - Math.pow(1 - p, 3);
          left.x = -80 + (W / 2 - 55 + 80) * ease;
          right.x = W + 80 - (W + 80 - (W / 2 + 55)) * ease;
          if (t > 900 && !s.state.clinked) {
            s.state.clinked = true;
            for (let i = 0; i < n(36); i++) {
              const a = -Math.PI / 2 + (s.rand() - 0.5) * 2.2;
              const speed = 160 + s.rand() * 320;
              s.particles.push({
                kind: 'dot',
                color: s.rand() > 0.4 ? '#ffe9a8' : '#ffffff',
                x: W / 2,
                y: H * 0.47,
                vx: Math.cos(a) * speed,
                vy: Math.sin(a) * speed,
                g: 220,
                size: 3 + s.rand() * 5,
                rot: 0,
                vr: 0,
                born: performance.now(),
                life: 1600 + s.rand() * 700,
              });
            }
            s.particles.push({ kind: 'emoji', emoji: '✨', x: W / 2, y: H * 0.42, vx: 0, vy: -20, g: 0, size: 70, rot: 0, vr: 0, born: performance.now(), life: 1200 });
          }
          if (t > 1000 && t < 3200 && s.rand() < 0.5) {
            s.particles.push({
              kind: 'dot',
              color: 'rgba(255,240,200,0.9)',
              x: W / 2 + (s.rand() - 0.5) * 140,
              y: H * 0.5,
              vx: (s.rand() - 0.5) * 20,
              vy: -(60 + s.rand() * 80),
              g: -10,
              size: 2 + s.rand() * 3,
              rot: 0,
              vr: 0,
              born: performance.now(),
              life: 1500,
            });
          }
        };
        break;
      }
      case 'roses': {
        const reds = ['#d7263d', '#ff4d6d', '#ff8fa3', '#c9184a', '#ffb3c1'];
        for (let i = 0; i < n(60); i++) {
          add({
            kind: 'petal',
            color: reds[Math.floor(rand() * reds.length)],
            x: rand() * W,
            y: -30 - rand() * 200,
            vx: (rand() - 0.5) * 40,
            vy: 60 + rand() * 80,
            g: 8,
            size: 10 + rand() * 12,
            rot: rand() * 6,
            vr: (rand() - 0.5) * 3,
            life: 4600,
            sway: 30 + rand() * 40,
            swayPhase: rand() * 6,
            born: now + rand() * 1400,
          });
        }
        for (let i = 0; i < 3; i++) {
          add({ kind: 'emoji', emoji: '🌹', x: 200 + i * 300 + rand() * 60, y: -60, vx: 0, vy: 90, g: 0, size: 54, rot: rand(), vr: 0.6, life: 4400, sway: 40, swayPhase: rand() * 6, born: now + i * 300 });
        }
        break;
      }
      case 'fireworks': {
        for (let i = 0; i < n(7); i++) {
          add({
            kind: 'rocket',
            color: '#fff3d6',
            x: 120 + rand() * 760,
            y: H + 10,
            vx: (rand() - 0.5) * 80,
            vy: -(H * 0.9 + rand() * H * 0.4),
            g: H * 0.55,
            size: 3,
            life: 900 + rand() * 400,
            born: now + i * 380 + rand() * 200,
            burst: { colors: FIREWORK_PALETTES[Math.floor(rand() * FIREWORK_PALETTES.length)]!, count: n(56) },
          });
        }
        show.duration = 5600;
        break;
      }
      case 'starfall': {
        for (let i = 0; i < n(14); i++) {
          const speed = 700 + rand() * 500;
          add({
            kind: 'streak',
            color: rand() > 0.5 ? '#fff6d6' : '#d6ecff',
            x: 200 + rand() * 900,
            y: -40 - rand() * 200,
            vx: -speed * 0.75,
            vy: speed * 0.5,
            g: 0,
            size: 2.5 + rand() * 2,
            life: 1400,
            born: now + rand() * 3000,
          });
        }
        add({ kind: 'emoji', emoji: '🌠', x: W * 0.8, y: H * 0.18, vx: -180, vy: 70, g: 0, size: 64, life: 3200 });
        break;
      }
    }

    this.shows.push(show);
    if (!this.raf) {
      this.lastFrame = performance.now();
      this.raf = requestAnimationFrame(this.frame);
    }
  }

  private frame = (now: number): void => {
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    const scale = (this.w / 1000) * this.dpr;
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    const H = (1000 * this.h) / Math.max(1, this.w);
    // Real elapsed time (capped), so a 120 Hz screen and a 60 Hz screen play at the same speed.
    const dt = Math.min(0.05, Math.max(0, (now - this.lastFrame) / 1000));
    this.lastFrame = now;

    for (const show of this.shows) {
      show.script?.(now - show.started, show, 1000, H);
      const spawned: Particle[] = [];
      show.particles = show.particles.filter((p) => {
        const age = now - p.born;
        if (age < 0) return true; // not born yet
        if (age > p.life) {
          if (p.kind === 'rocket' && p.burst) spawned.push(...burstFrom(p, show.rand, now));
          return false;
        }
        p.vy += p.g * dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.rot += p.vr * dt;
        if (p.bounce && p.y > H - 20 && p.vy > 0) {
          p.y = H - 20;
          p.vy *= -0.35;
          p.vx *= 0.7;
        }
        const fadeIn = Math.min(1, age / 250);
        const fadeOut = Math.min(1, (p.life - age) / 600);
        this.draw(p, fadeIn * fadeOut, age);
        return true;
      });
      show.particles.push(...spawned);
    }
    this.shows = this.shows.filter((s) => s.particles.length > 0 && now - s.started < s.duration + 4000);

    if (this.shows.length > 0) {
      this.raf = requestAnimationFrame(this.frame);
    } else {
      this.raf = 0;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    }
  };

  private draw(p: Particle, alpha: number, age: number): void {
    const ctx = this.ctx;
    const swayX = p.sway ? Math.sin(age / 500 + (p.swayPhase ?? 0)) * p.sway : 0;
    ctx.save();
    ctx.globalAlpha = Math.max(0, alpha);
    ctx.translate(p.x + swayX, p.y);
    ctx.rotate(p.rot);
    switch (p.kind) {
      case 'emoji': {
        const pop = p.emoji === '💋' ? 0.6 + Math.min(1, age / 500) * 0.4 + Math.sin(age / 120) * 0.03 : 1;
        ctx.font = `${p.size * pop}px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(p.emoji ?? '', 0, 0);
        break;
      }
      case 'dot': {
        ctx.fillStyle = p.color ?? '#fff';
        ctx.shadowColor = p.color ?? '#fff';
        ctx.shadowBlur = p.size * 2;
        ctx.beginPath();
        ctx.arc(0, 0, p.size, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
      case 'petal': {
        ctx.fillStyle = p.color ?? '#ff4d6d';
        ctx.beginPath();
        ctx.ellipse(0, 0, p.size, p.size * 0.55, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = 'rgba(255,255,255,0.18)';
        ctx.beginPath();
        ctx.ellipse(-p.size * 0.25, -p.size * 0.12, p.size * 0.45, p.size * 0.18, 0, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
      case 'streak':
      case 'rocket': {
        const len = p.kind === 'streak' ? 90 : 26;
        const speed = Math.hypot(p.vx, p.vy) || 1;
        const tx = (-p.vx / speed) * len;
        const ty = (-p.vy / speed) * len;
        const grad = ctx.createLinearGradient(0, 0, tx, ty);
        grad.addColorStop(0, p.color ?? '#fff');
        grad.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.strokeStyle = grad;
        ctx.lineWidth = p.size;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(tx, ty);
        ctx.stroke();
        ctx.fillStyle = '#fff';
        ctx.shadowColor = p.color ?? '#fff';
        ctx.shadowBlur = 12;
        ctx.beginPath();
        ctx.arc(0, 0, p.size, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
    }
    ctx.restore();
  }

  destroy(): void {
    cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.shows = [];
  }
}

function burstFrom(rocket: Particle, rand: () => number, now: number): Particle[] {
  const out: Particle[] = [];
  const { colors, count } = rocket.burst!;
  for (let i = 0; i < count; i++) {
    const a = (i / count) * Math.PI * 2 + rand() * 0.2;
    const speed = 140 + rand() * 180;
    out.push({
      kind: 'dot',
      color: colors[Math.floor(rand() * colors.length)],
      x: rocket.x,
      y: rocket.y,
      vx: Math.cos(a) * speed,
      vy: Math.sin(a) * speed,
      g: 110,
      size: 2.4 + rand() * 2.2,
      rot: 0,
      vr: 0,
      born: now,
      life: 1300 + rand() * 600,
    });
  }
  return out;
}
