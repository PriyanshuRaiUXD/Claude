import fs from 'node:fs';
import path from 'node:path';
import type { FrameId } from '../shared/catalog';

export interface ProRecord {
  customerId: string;
  subscriptionId: string;
  /** Stripe subscription status: active, trialing, past_due, canceled, … */
  status: string;
  currentPeriodEnd?: number;
  cancelAtPeriodEnd?: boolean;
  /** SHA-256 hashes of tokens that may open the billing portal for this room. */
  manageTokenHashes: string[];
}

export interface RoomRecord {
  id: string;
  createdAt: number;
  lastActiveAt: number;
  sparks: number;
  frame: FrameId;
  passExpiresAt?: number;
  pro?: ProRecord;
  /** Free-tier session clock. Running until endsAt, then locked until cooldownEndsAt. */
  session?: { endsAt: number; cooldownEndsAt: number };
  /** Payment references already applied to this room (idempotency). */
  fulfilled: string[];
}

interface Snapshot {
  version: 1;
  rooms: RoomRecord[];
  events: string[];
}

const MAX_EVENTS = 2000;
const MAX_FULFILLED = 200;

/**
 * Durable room storage.
 *
 * Rooms are tiny (a few hundred bytes) and written rarely (creation, purchases, gifts), so the
 * whole set lives in memory and is flushed atomically to one JSON file. That keeps local setup at
 * zero dependencies. Every caller goes through this class, so moving to Postgres or Redis for a
 * multi-instance deployment means reimplementing these methods and nothing else.
 */
export class Store {
  private rooms = new Map<string, RoomRecord>();
  private events: string[] = [];
  private eventSet = new Set<string>();
  private timer: NodeJS.Timeout | null = null;
  private readonly file: string | null;

  /** Pass `null` for an in-memory store (tests). */
  constructor(dataDir: string | null) {
    this.file = dataDir ? path.join(dataDir, 'loveseat.json') : null;
    if (!this.file) return;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    if (!fs.existsSync(this.file)) return;
    try {
      const snapshot = JSON.parse(fs.readFileSync(this.file, 'utf8')) as Snapshot;
      for (const room of snapshot.rooms ?? []) this.rooms.set(room.id, room);
      this.events = snapshot.events ?? [];
      this.eventSet = new Set(this.events);
    } catch (err) {
      // Never silently start empty over a corrupt file: that would wipe paid entitlements on the next save.
      const backup = `${this.file}.corrupt-${Date.now()}`;
      fs.copyFileSync(this.file, backup);
      console.error(`[store] ${this.file} could not be parsed (${(err as Error).message}). A copy was kept at ${backup}.`);
    }
  }

  get(id: string): RoomRecord | undefined {
    return this.rooms.get(id);
  }

  has(id: string): boolean {
    return this.rooms.has(id);
  }

  insert(room: RoomRecord): void {
    this.rooms.set(room.id, room);
    this.touch();
  }

  findBySubscription(subscriptionId: string): RoomRecord | undefined {
    for (const room of this.rooms.values()) {
      if (room.pro?.subscriptionId === subscriptionId) return room;
    }
    return undefined;
  }

  /** Returns true the first time a payment reference is seen for a room. */
  markFulfilled(room: RoomRecord, ref: string): boolean {
    if (room.fulfilled.includes(ref)) return false;
    room.fulfilled.push(ref);
    if (room.fulfilled.length > MAX_FULFILLED) room.fulfilled.splice(0, room.fulfilled.length - MAX_FULFILLED);
    this.touch();
    return true;
  }

  /** Returns true the first time a webhook event id is seen. */
  markEvent(eventId: string): boolean {
    if (this.eventSet.has(eventId)) return false;
    this.eventSet.add(eventId);
    this.events.push(eventId);
    if (this.events.length > MAX_EVENTS) {
      for (const old of this.events.splice(0, this.events.length - MAX_EVENTS)) this.eventSet.delete(old);
    }
    this.touch();
    return true;
  }

  /** Drops never-paid rooms nobody has opened for `maxIdleMs`. Paid history is always kept. */
  prune(maxIdleMs: number, now = Date.now()): number {
    let removed = 0;
    for (const room of this.rooms.values()) {
      const neverPaid = !room.pro && !room.passExpiresAt && room.fulfilled.length === 0;
      if (neverPaid && now - room.lastActiveAt > maxIdleMs) {
        this.rooms.delete(room.id);
        removed++;
      }
    }
    if (removed > 0) this.touch();
    return removed;
  }

  /** Schedule a write. Call after mutating a record. */
  touch(): void {
    if (!this.file || this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush();
    }, 150);
    this.timer.unref();
  }

  /** Write immediately (also used on shutdown). */
  flush(): void {
    if (!this.file) return;
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    const snapshot: Snapshot = { version: 1, rooms: [...this.rooms.values()], events: this.events };
    const tmp = `${this.file}.tmp`;
    try {
      fs.writeFileSync(tmp, JSON.stringify(snapshot));
      fs.renameSync(tmp, this.file); // atomic on the same filesystem
    } catch (err) {
      console.error(`[store] failed to persist: ${(err as Error).message}`);
    }
  }
}
