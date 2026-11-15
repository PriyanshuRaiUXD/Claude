import {
  FRAMES,
  GIFTS,
  GIFT_COOLDOWN_MS,
  PLANS,
  STARTER_SPARKS,
  entitlementFor,
  type Entitlement,
  type FrameId,
  type ProductId,
  type Tier,
} from '../shared/catalog';
import type {
  FrameResult,
  GiftPlay,
  GiftResult,
  Participant,
  RoomState,
  SessionInfo,
  StreamStartResult,
  StreamState,
} from '../shared/types';
import { randomId } from './ids';
import type { ProRecord, RoomRecord, Store } from './store';

/** Statuses that keep Couples Pro unlocked. past_due keeps access while Stripe retries the card. */
const PRO_ACTIVE = new Set(['active', 'trialing', 'past_due']);
const MAX_PARTICIPANTS = 2;
const WARNING_BEFORE_MS = 5 * 60_000;
const MAX_TIMER_MS = 2 ** 31 - 1;

interface LiveParticipant extends Participant {
  clientId: string;
  socketId: string | null;
  graceTimer?: NodeJS.Timeout;
  lastGiftAt: number;
}

interface LiveRoom {
  id: string;
  participants: Map<string, LiveParticipant>;
  stream: StreamState;
  timers: NodeJS.Timeout[];
}

/** Everything the room layer needs to tell connected browsers. Implemented over Socket.IO in socket.ts. */
export interface RoomEmitter {
  state(roomId: string, state: RoomState): void;
  toRoom(roomId: string, event: 'peer:joined' | 'peer:left', payload: { id: string }, exceptSocketId?: string): void;
  gift(roomId: string, play: GiftPlay): void;
  sessionWarning(roomId: string, msLeft: number): void;
  sessionExpired(roomId: string, cooldownEndsAt: number): void;
  upgraded(roomId: string, tier: 'pass' | 'pro'): void;
  sparksAdded(roomId: string, amount: number, sparks: number): void;
  replaced(socketId: string): void;
}

export interface RoomOptions {
  freeSessionMs: number;
  freeCooldownMs: number;
  reconnectGraceMs: number;
  now?: () => number;
}

export type JoinOutcome =
  | { ok: true; participant: LiveParticipant; replacedSocketId: string | null }
  | { ok: false; error: 'not_found' | 'full' };

export function cleanName(raw: unknown): string {
  const name = typeof raw === 'string' ? raw.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 24) : '';
  return name || 'Partner';
}

/**
 * Authoritative room state: who is here, what is on screen, which tier the room has, the free
 * session clock and the shared Sparks wallet. Durable fields live in the Store; presence lives here.
 */
export class Rooms {
  private live = new Map<string, LiveRoom>();
  private emitter: RoomEmitter | null = null;
  private readonly now: () => number;

  constructor(
    private readonly store: Store,
    private readonly opts: RoomOptions,
  ) {
    this.now = opts.now ?? Date.now;
  }

  attach(emitter: RoomEmitter): void {
    this.emitter = emitter;
  }

  /** Tell an older tab of the same browser that a newer one took its seat. */
  attachReplaced(socketId: string): void {
    this.emitter?.replaced(socketId);
  }

  // ---------------------------------------------------------------- records --

  create(): RoomRecord {
    let id = randomId();
    while (this.store.has(id)) id = randomId();
    const now = this.now();
    const record: RoomRecord = { id, createdAt: now, lastActiveAt: now, sparks: STARTER_SPARKS, frame: 'none', fulfilled: [] };
    this.store.insert(record);
    return record;
  }

  record(roomId: string): RoomRecord | undefined {
    return this.store.get(roomId);
  }

  tier(record: RoomRecord): Tier {
    if (record.pro && PRO_ACTIVE.has(record.pro.status)) return 'pro';
    if (record.passExpiresAt && record.passExpiresAt > this.now()) return 'pass';
    return 'free';
  }

  entitlement(record: RoomRecord): Entitlement {
    return entitlementFor(this.tier(record), {
      passExpiresAt: record.passExpiresAt && record.passExpiresAt > this.now() ? record.passExpiresAt : undefined,
      proStatus: record.pro?.status,
    });
  }

  session(record: RoomRecord): SessionInfo {
    const limitMs = this.opts.freeSessionMs;
    if (this.tier(record) !== 'free' || !record.session) return { state: 'idle', limitMs };
    const now = this.now();
    const { endsAt, cooldownEndsAt } = record.session;
    if (now < endsAt) return { state: 'running', limitMs, endsAt };
    if (now < cooldownEndsAt) return { state: 'cooldown', limitMs, cooldownEndsAt };
    return { state: 'idle', limitMs };
  }

  state(roomId: string): RoomState | null {
    const record = this.store.get(roomId);
    if (!record) return null;
    const live = this.live.get(roomId);
    return {
      id: roomId,
      participants: live ? [...live.participants.values()].map(publicParticipant) : [],
      entitlement: this.entitlement(record),
      session: this.session(record),
      stream: live?.stream ?? { mode: 'none' },
      sparks: record.sparks,
      // A frame chosen during Pro is kept but not shown after Pro ends.
      frame: this.tier(record) === 'pro' ? record.frame : 'none',
    };
  }

  participantCount(roomId: string): number {
    return this.live.get(roomId)?.participants.size ?? 0;
  }

  /** Seats held by a live socket. A seat in its reconnect grace period may be about to be reclaimed. */
  connectedCount(roomId: string): number {
    let n = 0;
    for (const p of this.live.get(roomId)?.participants.values() ?? []) if (p.connected) n++;
    return n;
  }

  // --------------------------------------------------------------- presence --

  join(roomId: string, clientId: string, socketId: string, name: string, micOn: boolean, camOn: boolean, stillSharing = false): JoinOutcome {
    const record = this.store.get(roomId);
    if (!record) return { ok: false, error: 'not_found' };
    const live = this.ensureLive(roomId);

    // The same browser coming back (reload, network blip, second tab) takes over its old seat.
    for (const p of live.participants.values()) {
      if (p.clientId !== clientId) continue;
      if (p.graceTimer) clearTimeout(p.graceTimer);
      p.graceTimer = undefined;
      const replacedSocketId = p.socketId && p.socketId !== socketId ? p.socketId : null;
      Object.assign(p, { socketId, connected: true, name: cleanName(name), micOn, camOn });
      // After a reload the old capture is gone; after a socket blip it is still running.
      if (live.stream.mode === 'screen' && live.stream.by === p.id && !stillSharing) live.stream = { mode: 'none' };
      this.touchRecord(record);
      return { ok: true, participant: p, replacedSocketId };
    }

    if (live.participants.size >= MAX_PARTICIPANTS) return { ok: false, error: 'full' };

    const participant: LiveParticipant = {
      id: randomId(10),
      clientId,
      socketId,
      name: cleanName(name),
      micOn,
      camOn,
      connected: true,
      lastGiftAt: 0,
    };
    live.participants.set(participant.id, participant);
    this.touchRecord(record);
    return { ok: true, participant, replacedSocketId: null };
  }

  /** Socket went away. Keep the seat for a grace period so reloads and blips are seamless. */
  disconnect(roomId: string, participantId: string, socketId: string): void {
    const live = this.live.get(roomId);
    const p = live?.participants.get(participantId);
    if (!live || !p || p.socketId !== socketId) return; // already taken over by a newer socket
    p.socketId = null;
    p.connected = false;
    if (p.graceTimer) clearTimeout(p.graceTimer);
    p.graceTimer = setTimeout(() => this.remove(roomId, participantId), this.opts.reconnectGraceMs);
    p.graceTimer.unref?.();
    this.broadcast(roomId);
  }

  private remove(roomId: string, participantId: string): void {
    const live = this.live.get(roomId);
    if (!live?.participants.delete(participantId)) return;
    if (live.stream.mode !== 'none' && live.stream.by === participantId) live.stream = { mode: 'none' };
    this.emitter?.toRoom(roomId, 'peer:left', { id: participantId });
    if (live.participants.size === 0) {
      for (const t of live.timers) clearTimeout(t);
      this.live.delete(roomId);
      return;
    }
    this.broadcast(roomId);
  }

  setMedia(roomId: string, participantId: string, micOn: boolean, camOn: boolean): void {
    const p = this.live.get(roomId)?.participants.get(participantId);
    if (!p) return;
    p.micOn = micOn;
    p.camOn = camOn;
    this.broadcast(roomId);
  }

  setName(roomId: string, participantId: string, name: string): void {
    const p = this.live.get(roomId)?.participants.get(participantId);
    if (!p) return;
    p.name = cleanName(name);
    this.broadcast(roomId);
  }

  // ----------------------------------------------------------------- stream --

  startStream(roomId: string, participantId: string, next: StreamState): StreamStartResult {
    const record = this.store.get(roomId);
    const live = this.live.get(roomId);
    if (!record || !live?.participants.has(participantId)) return { ok: false, error: 'not_in_room' };
    if (live.stream.mode !== 'none' && live.stream.by !== participantId && this.isConnected(live, live.stream.by)) {
      return { ok: false, error: 'busy' };
    }

    if (this.tier(record) === 'free') {
      const session = this.session(record);
      if (session.state === 'cooldown') return { ok: false, error: 'session_locked', cooldownEndsAt: session.cooldownEndsAt! };
      if (session.state === 'idle') {
        const now = this.now();
        record.session = { endsAt: now + this.opts.freeSessionMs, cooldownEndsAt: now + this.opts.freeSessionMs + this.opts.freeCooldownMs };
        this.store.touch();
      }
    }

    live.stream = next;
    this.schedule(roomId);
    this.broadcast(roomId);
    return { ok: true };
  }

  stopStream(roomId: string, participantId: string): void {
    const live = this.live.get(roomId);
    if (!live || live.stream.mode === 'none') return;
    // Either partner may end what is playing.
    if (!live.participants.has(participantId)) return;
    live.stream = { mode: 'none' };
    this.broadcast(roomId);
  }

  urlControl(roomId: string, participantId: string, playing: boolean, position: number): void {
    const live = this.live.get(roomId);
    if (!live?.participants.has(participantId) || live.stream.mode !== 'url') return;
    if (!Number.isFinite(position) || position < 0) return;
    live.stream = { ...live.stream, url: { ...live.stream.url, playing, position, updatedAt: this.now() } };
    this.broadcast(roomId);
  }

  // ------------------------------------------------------------ gifts/frames --

  sendGift(roomId: string, participantId: string, giftId: string): GiftResult {
    const record = this.store.get(roomId);
    const p = this.live.get(roomId)?.participants.get(participantId);
    if (!record || !p) return { ok: false, error: 'not_in_room' };
    const gift = GIFTS.find((g) => g.id === giftId);
    if (!gift) return { ok: false, error: 'unknown_gift' };
    const now = this.now();
    if (now - p.lastGiftAt < GIFT_COOLDOWN_MS) return { ok: false, error: 'cooldown', sparks: record.sparks };
    if (record.sparks < gift.cost) return { ok: false, error: 'insufficient', sparks: record.sparks };

    record.sparks -= gift.cost;
    p.lastGiftAt = now;
    this.touchRecord(record);
    this.emitter?.gift(roomId, {
      id: randomId(8),
      giftId: gift.id,
      from: p.id,
      fromName: p.name,
      seed: Math.floor(Math.random() * 2 ** 31),
    });
    if (gift.cost > 0) this.broadcast(roomId);
    return { ok: true, sparks: record.sparks };
  }

  setFrame(roomId: string, participantId: string, frameId: string): FrameResult {
    const record = this.store.get(roomId);
    if (!record || !this.live.get(roomId)?.participants.has(participantId)) return { ok: false, error: 'not_in_room' };
    const frame = FRAMES.find((f) => f.id === frameId);
    if (!frame) return { ok: false, error: 'unknown_frame' };
    if (frame.pro && !this.entitlement(record).frames) return { ok: false, error: 'pro_required' };
    record.frame = frame.id as FrameId;
    this.touchRecord(record);
    this.broadcast(roomId);
    return { ok: true };
  }

  // ------------------------------------------------------------- purchases --

  /**
   * Apply a completed purchase to a room. `ref` (Stripe Checkout Session id, invoice id or demo
   * token id) makes this idempotent: webhooks, the return-page verification and retries can all
   * call it and the purchase is applied exactly once. Returns false if `ref` was already applied.
   */
  fulfill(roomId: string, ref: string, product: ProductId, pro?: Omit<ProRecord, 'manageTokenHashes'>): boolean {
    const record = this.store.get(roomId);
    if (!record) return false;
    if (!this.store.markFulfilled(record, ref)) return false;
    const before = this.tier(record);

    if (product === 'pass') {
      const base = Math.max(this.now(), record.passExpiresAt ?? 0);
      record.passExpiresAt = base + PLANS.pass.durationMs;
      this.addSparks(record, PLANS.pass.bonusSparks);
    } else if (product === 'pro') {
      if (!pro) throw new Error('Pro fulfilment needs subscription details');
      record.pro = { ...pro, manageTokenHashes: record.pro?.manageTokenHashes ?? [] };
    } else {
      const sparks = { sparks_15: 15, sparks_50: 50, sparks_150: 150 }[product];
      this.addSparks(record, sparks);
    }
    this.store.touch();
    this.afterEntitlementChange(record, before);
    return true;
  }

  /** Subscription changed in Stripe (renewed, past due, cancelled…). */
  updatePro(record: RoomRecord, patch: Partial<Omit<ProRecord, 'manageTokenHashes'>>): void {
    if (!record.pro) return;
    const before = this.tier(record);
    record.pro = { ...record.pro, ...patch };
    this.store.touch();
    this.afterEntitlementChange(record, before);
  }

  addManageToken(record: RoomRecord, tokenHash: string): void {
    if (!record.pro) return;
    record.pro.manageTokenHashes = [...record.pro.manageTokenHashes.slice(-4), tokenHash];
    this.store.touch();
  }

  addSparks(record: RoomRecord, amount: number): void {
    record.sparks += amount;
    this.store.touch();
    if (this.live.has(record.id)) {
      this.emitter?.sparksAdded(record.id, amount, record.sparks);
      this.broadcast(record.id);
    }
  }

  // --------------------------------------------------------------- internals --

  private afterEntitlementChange(record: RoomRecord, before: Tier): void {
    const after = this.tier(record);
    if (after !== 'free') record.session = undefined; // paid rooms have no clock
    if (!this.live.has(record.id)) return;
    if (after !== before && after !== 'free') this.emitter?.upgraded(record.id, after);
    this.schedule(record.id);
    this.broadcast(record.id);
  }

  private ensureLive(roomId: string): LiveRoom {
    let live = this.live.get(roomId);
    if (!live) {
      live = { id: roomId, participants: new Map(), stream: { mode: 'none' }, timers: [] };
      this.live.set(roomId, live);
      this.schedule(roomId);
    }
    return live;
  }

  private isConnected(live: LiveRoom, participantId: string): boolean {
    return live.participants.get(participantId)?.connected ?? false;
  }

  /** (Re)arm the timers that matter for this room: session warning, session end, cooldown end, pass expiry. */
  private schedule(roomId: string): void {
    const live = this.live.get(roomId);
    const record = this.store.get(roomId);
    if (!live || !record) return;
    for (const t of live.timers) clearTimeout(t);
    live.timers = [];
    const now = this.now();
    const at = (when: number, fn: () => void) => {
      const delay = when - now;
      if (delay < 0 || delay > MAX_TIMER_MS) return;
      const t = setTimeout(fn, delay);
      t.unref?.();
      live.timers.push(t);
    };

    const session = this.session(record);
    if (session.state === 'running') {
      const endsAt = session.endsAt!;
      at(endsAt - WARNING_BEFORE_MS, () => this.emitter?.sessionWarning(roomId, Math.max(0, endsAt - this.now())));
      at(endsAt, () => this.expireSession(roomId));
    } else if (session.state === 'cooldown') {
      at(session.cooldownEndsAt!, () => this.broadcast(roomId));
    }
    if (record.passExpiresAt && this.tier(record) === 'pass') {
      at(record.passExpiresAt, () => this.passExpired(roomId));
    }
  }

  private expireSession(roomId: string): void {
    const live = this.live.get(roomId);
    const record = this.store.get(roomId);
    if (!live || !record || this.tier(record) !== 'free' || !record.session) return;
    // Calls stay up: only the shared stream ends.
    const hadStream = live.stream.mode !== 'none';
    live.stream = { mode: 'none' };
    if (hadStream) this.emitter?.sessionExpired(roomId, record.session.cooldownEndsAt);
    this.schedule(roomId);
    this.broadcast(roomId);
  }

  private passExpired(roomId: string): void {
    const live = this.live.get(roomId);
    const record = this.store.get(roomId);
    if (!live || !record || this.tier(record) !== 'free') return;
    // Mid-movie when the pass runs out: start a fresh free session instead of cutting the screen.
    if (live.stream.mode !== 'none') {
      const now = this.now();
      record.session = { endsAt: now + this.opts.freeSessionMs, cooldownEndsAt: now + this.opts.freeSessionMs + this.opts.freeCooldownMs };
      this.store.touch();
    }
    this.schedule(roomId);
    this.broadcast(roomId);
  }

  private touchRecord(record: RoomRecord): void {
    record.lastActiveAt = this.now();
    this.store.touch();
  }

  broadcast(roomId: string): void {
    const state = this.state(roomId);
    if (state) this.emitter?.state(roomId, state);
  }
}

function publicParticipant(p: LiveParticipant): Participant {
  return { id: p.id, name: p.name, micOn: p.micOn, camOn: p.camOn, connected: p.connected };
}
