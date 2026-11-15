import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';
import type { HouseAd, IceServer } from '../shared/types';

// Set by scripts/build-server.mjs, so `npm start` is production without shell-specific env syntax.
if (process.env.LOVESEAT_BUILT && !process.env.NODE_ENV) process.env.NODE_ENV = 'production';

const env = process.env;

function num(value: string | undefined, fallback: number): number {
  if (value === undefined || value.trim() === '') return fallback;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

function clean(value: string | undefined): string {
  return (value ?? '').trim();
}

const isProd = env.NODE_ENV === 'production';
const stripeSecretKey = clean(env.STRIPE_SECRET_KEY);

/**
 * stripe   — real Stripe Checkout (test or live keys).
 * demo     — no Stripe key: a built-in simulated checkout so the whole product can be exercised locally.
 * disabled — production without a Stripe key: purchases are refused rather than given away.
 */
function billingMode(): 'stripe' | 'demo' | 'disabled' {
  if (stripeSecretKey) return 'stripe';
  if (!isProd || clean(env.ALLOW_DEMO_BILLING) === 'true') return 'demo';
  return 'disabled';
}

function iceServers(): IceServer[] {
  const raw = clean(env.ICE_SERVERS_JSON);
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as IceServer[];
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    } catch {
      console.warn('[config] ICE_SERVERS_JSON is not valid JSON — falling back to the default STUN servers.');
    }
  }
  const stun = clean(env.STUN_URLS) || 'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302';
  return [{ urls: stun.split(',').map((s) => s.trim()).filter(Boolean) }];
}

const DEFAULT_HOUSE_ADS: HouseAd[] = [
  {
    id: 'house-pass',
    sponsor: 'Loveseat',
    title: 'Tonight only? Grab a Date Night Pass.',
    body: '24 hours of 1080p60 with no time limit — $1.99, no subscription.',
    cta: 'Get the pass',
    href: 'action:pass',
  },
  {
    id: 'house-pro',
    sponsor: 'Loveseat',
    title: 'Couples Pro covers both of you.',
    body: 'Unlimited HD movie nights, cozy frames and zero ads on one plan.',
    cta: 'See Couples Pro',
    href: 'action:pro',
  },
  {
    id: 'house-gifts',
    sponsor: 'Loveseat',
    title: 'Clink glasses from 4,000 miles away.',
    body: 'Send champagne, popcorn and fireworks across both screens with Sparks.',
    cta: 'Open the gift shop',
    href: 'action:gifts',
  },
];

function houseAds(): HouseAd[] {
  const file = clean(env.ADS_FILE);
  if (!file) return DEFAULT_HOUSE_ADS;
  try {
    const parsed = JSON.parse(fs.readFileSync(path.resolve(file), 'utf8')) as HouseAd[];
    const valid = parsed.filter(
      (ad) =>
        ad &&
        typeof ad.id === 'string' &&
        typeof ad.title === 'string' &&
        typeof ad.href === 'string' &&
        (ad.href.startsWith('https://') || ad.href.startsWith('action:')),
    );
    if (valid.length > 0) return valid;
    console.warn(`[config] ${file} contains no valid ads — using the built-in house ads.`);
  } catch (err) {
    console.warn(`[config] Could not read ADS_FILE (${file}): ${(err as Error).message}`);
  }
  return DEFAULT_HOUSE_ADS;
}

const adsenseClient = clean(env.ADSENSE_CLIENT);
const adsenseSlot = clean(env.ADSENSE_SLOT);

export const config = {
  isProd,
  port: num(env.PORT, 3001),
  /** Public origin used for Stripe redirect URLs. Required in production. */
  appUrl: clean(env.APP_URL).replace(/\/+$/, '') || null,
  /** Number of reverse proxies in front of the app (0 = none). */
  trustProxy: num(env.TRUST_PROXY, 0),
  dataDir: path.resolve(clean(env.DATA_DIR) || 'data'),

  billingMode: billingMode(),
  stripeSecretKey,
  stripeWebhookSecret: clean(env.STRIPE_WEBHOOK_SECRET),
  /** Optional pre-created recurring Price for Couples Pro. Without it the price is defined inline. */
  stripeProPriceId: clean(env.STRIPE_PRO_PRICE_ID),

  freeSessionMs: Math.max(5_000, num(env.FREE_SESSION_MINUTES, 60) * 60_000),
  freeCooldownMs: num(env.FREE_COOLDOWN_MINUTES, 20) * 60_000,
  /** How long a dropped socket may take to reconnect before the partner is told they left. */
  reconnectGraceMs: num(env.RECONNECT_GRACE_SECONDS, 10) * 1000,

  iceServers: iceServers(),
  turn: {
    urls: clean(env.TURN_URLS).split(',').map((s) => s.trim()).filter(Boolean),
    /** Static long-term credentials… */
    username: clean(env.TURN_USERNAME),
    credential: clean(env.TURN_CREDENTIAL),
    /** …or a coturn `static-auth-secret`, from which short-lived credentials are minted per join. */
    secret: clean(env.TURN_SECRET),
  },

  ads: {
    adsense: adsenseClient && adsenseSlot ? { client: adsenseClient, slot: adsenseSlot } : null,
    house: houseAds(),
  },
};

export type Config = typeof config;
