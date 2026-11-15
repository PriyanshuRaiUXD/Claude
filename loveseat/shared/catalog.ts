/**
 * Single source of truth for everything that has a price, a limit or a tier.
 * Imported by both the server (authoritative) and the client (display only).
 * The server never trusts an amount, cost or tier sent by a browser.
 */

export type Tier = 'free' | 'pass' | 'pro';
export type QualityId = 'sd' | 'hd';

export interface VideoTarget {
  width: number;
  height: number;
  frameRate: number;
  /** Upper bound for the encoder, bits per second. */
  maxBitrate: number;
}

export interface QualityProfile {
  id: QualityId;
  label: string;
  screen: VideoTarget;
  camera: VideoTarget;
  /** Stereo system-audio bitrate, bits per second. */
  streamAudioBitrate: number;
}

export const QUALITY: Record<QualityId, QualityProfile> = {
  sd: {
    id: 'sd',
    label: '720p',
    screen: { width: 1280, height: 720, frameRate: 30, maxBitrate: 2_500_000 },
    camera: { width: 1280, height: 720, frameRate: 30, maxBitrate: 900_000 },
    streamAudioBitrate: 128_000,
  },
  hd: {
    id: 'hd',
    label: '1080p60',
    screen: { width: 1920, height: 1080, frameRate: 60, maxBitrate: 8_000_000 },
    camera: { width: 1920, height: 1080, frameRate: 60, maxBitrate: 2_500_000 },
    streamAudioBitrate: 256_000,
  },
};

/**
 * Rungs the adaptive controller walks when the network or CPU struggles.
 * Ordered best → worst. A room's tier decides the highest rung it may use.
 */
export interface QualityRung {
  label: string;
  height: number;
  frameRate: number;
  maxBitrate: number;
  minTier: QualityId;
}

export const QUALITY_LADDER: QualityRung[] = [
  { label: '1080p60', height: 1080, frameRate: 60, maxBitrate: 8_000_000, minTier: 'hd' },
  { label: '1080p30', height: 1080, frameRate: 30, maxBitrate: 5_000_000, minTier: 'hd' },
  { label: '720p30', height: 720, frameRate: 30, maxBitrate: 2_500_000, minTier: 'sd' },
  { label: '540p30', height: 540, frameRate: 30, maxBitrate: 1_200_000, minTier: 'sd' },
  { label: '360p24', height: 360, frameRate: 24, maxBitrate: 600_000, minTier: 'sd' },
];

// ---------------------------------------------------------------- products --

export const HOUR = 60 * 60 * 1000;

export const PLANS = {
  pro: {
    id: 'pro' as const,
    name: 'Couples Pro',
    tagline: 'One subscription. Both of you.',
    amount: 799,
    currency: 'usd',
    interval: 'month' as const,
    /** Sparks added to the room wallet on every paid invoice. */
    monthlySparks: 60,
    perks: [
      'True 1080p / 60fps streaming',
      'Unlimited session length',
      'Cozy room frames',
      'No lobby ads — for both of you',
      '60 gift Sparks every month',
    ],
  },
  pass: {
    id: 'pass' as const,
    name: 'Date Night Pass',
    tagline: '24 hours of the good stuff. No subscription.',
    amount: 199,
    currency: 'usd',
    durationMs: 24 * HOUR,
    bonusSparks: 5,
    perks: ['1080p / 60fps for 24 hours', 'No 60-minute limit', 'No lobby ads', '5 bonus gift Sparks'],
  },
};

export interface SparkPack {
  id: 'sparks_15' | 'sparks_50' | 'sparks_150';
  name: string;
  sparks: number;
  amount: number;
  currency: string;
  badge?: string;
}

export const SPARK_PACKS: SparkPack[] = [
  { id: 'sparks_15', name: '15 Sparks', sparks: 15, amount: 199, currency: 'usd' },
  { id: 'sparks_50', name: '50 Sparks', sparks: 50, amount: 499, currency: 'usd', badge: 'Most loved' },
  { id: 'sparks_150', name: '150 Sparks', sparks: 150, amount: 1199, currency: 'usd', badge: 'Best value' },
];

export type ProductId = 'pro' | 'pass' | SparkPack['id'];

export const PRODUCT_IDS: ProductId[] = ['pro', 'pass', 'sparks_15', 'sparks_50', 'sparks_150'];

export interface ProductInfo {
  id: ProductId;
  name: string;
  description: string;
  amount: number;
  currency: string;
  recurring: boolean;
}

export function productInfo(id: ProductId): ProductInfo {
  if (id === 'pro') {
    return {
      id,
      name: PLANS.pro.name,
      description: 'Unlimited 1080p60 co-watching, cozy frames and no ads for both partners in your room.',
      amount: PLANS.pro.amount,
      currency: PLANS.pro.currency,
      recurring: true,
    };
  }
  if (id === 'pass') {
    return {
      id,
      name: PLANS.pass.name,
      description: '24 hours of unlimited 1080p60 co-watching for your room. One-time payment.',
      amount: PLANS.pass.amount,
      currency: PLANS.pass.currency,
      recurring: false,
    };
  }
  const pack = SPARK_PACKS.find((p) => p.id === id);
  if (!pack) throw new Error(`Unknown product: ${String(id)}`);
  return {
    id,
    name: `${pack.name} gift pack`,
    description: `${pack.sparks} Sparks for date-night gifts, shared by both partners in your room.`,
    amount: pack.amount,
    currency: pack.currency,
    recurring: false,
  };
}

export function formatPrice(amount: number, currency = 'usd'): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: currency.toUpperCase() }).format(amount / 100);
}

// ------------------------------------------------------------------- gifts --

export type GiftId = 'hearts' | 'popcorn' | 'kiss' | 'champagne' | 'roses' | 'fireworks' | 'starfall';

export interface Gift {
  id: GiftId;
  name: string;
  emoji: string;
  /** Price in Sparks. 0 = free for everyone. */
  cost: number;
  blurb: string;
}

export const GIFTS: Gift[] = [
  { id: 'hearts', name: 'Floating hearts', emoji: '💕', cost: 0, blurb: 'Always free' },
  { id: 'popcorn', name: 'Popcorn toss', emoji: '🍿', cost: 1, blurb: 'Throw a handful' },
  { id: 'kiss', name: 'Blow a kiss', emoji: '💋', cost: 1, blurb: 'Across the miles' },
  { id: 'champagne', name: 'Champagne clink', emoji: '🥂', cost: 2, blurb: 'Cheers to us' },
  { id: 'roses', name: 'Rose petals', emoji: '🌹', cost: 2, blurb: 'A slow, soft shower' },
  { id: 'fireworks', name: 'Fireworks', emoji: '🎆', cost: 3, blurb: 'Light up the room' },
  { id: 'starfall', name: 'Shooting stars', emoji: '🌠', cost: 3, blurb: 'Make a wish' },
];

/** Every new room gets a few Sparks so the first paid gift is a tap away. */
export const STARTER_SPARKS = 3;
/** Minimum gap between gifts from the same person. */
export const GIFT_COOLDOWN_MS = 1500;

// ------------------------------------------------------------------ frames --

export type FrameId = 'none' | 'rosegold' | 'ember' | 'polaroid' | 'neon' | 'moonlight';

export interface Frame {
  id: FrameId;
  name: string;
  pro: boolean;
}

export const FRAMES: Frame[] = [
  { id: 'none', name: 'Clean', pro: false },
  { id: 'rosegold', name: 'Rose gold', pro: true },
  { id: 'ember', name: 'Fireside', pro: true },
  { id: 'polaroid', name: 'Polaroid', pro: true },
  { id: 'neon', name: 'Neon diner', pro: true },
  { id: 'moonlight', name: 'Moonlight', pro: true },
];

// ------------------------------------------------------------ entitlements --

export interface Entitlement {
  tier: Tier;
  quality: QualityId;
  /** No 60-minute session cap. */
  unlimited: boolean;
  /** Lobby ads are shown. */
  ads: boolean;
  /** Cozy frames are unlocked. */
  frames: boolean;
  /** When a Date Night Pass runs out (epoch ms). */
  passExpiresAt?: number;
  /** Stripe subscription status, when the room has (or had) Couples Pro. */
  proStatus?: string;
}

export function entitlementFor(tier: Tier, extra: Pick<Entitlement, 'passExpiresAt' | 'proStatus'> = {}): Entitlement {
  const paid = tier !== 'free';
  return {
    tier,
    quality: paid ? 'hd' : 'sd',
    unlimited: paid,
    ads: !paid,
    frames: tier === 'pro',
    ...extra,
  };
}
