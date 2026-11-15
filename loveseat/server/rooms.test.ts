import assert from 'node:assert/strict';
import { test } from 'node:test';
import { STARTER_SPARKS } from '../shared/catalog';
import { Rooms, type RoomEmitter } from './rooms';
import { Store } from './store';

function setup(sessionMs = 60_000, cooldownMs = 20_000) {
  let now = 1_700_000_000_000;
  const events: string[] = [];
  const store = new Store(null);
  const rooms = new Rooms(store, { freeSessionMs: sessionMs, freeCooldownMs: cooldownMs, reconnectGraceMs: 50, now: () => now });
  const emitter: RoomEmitter = {
    state: () => {},
    toRoom: (_r, e) => events.push(e),
    gift: () => events.push('gift'),
    sessionWarning: () => events.push('warning'),
    sessionExpired: () => events.push('expired'),
    upgraded: (_r, t) => events.push(`upgraded:${t}`),
    sparksAdded: () => events.push('sparks'),
    replaced: () => events.push('replaced'),
  };
  rooms.attach(emitter);
  return { rooms, store, events, advance: (ms: number) => (now += ms) };
}

test('a room seats exactly two people, and the same browser reclaims its seat', () => {
  const { rooms } = setup();
  const { id } = rooms.create();
  const a = rooms.join(id, 'client-aaaa', 's1', 'Ana', true, true);
  const b = rooms.join(id, 'client-bbbb', 's2', 'Ben', true, true);
  assert.ok(a.ok && b.ok);
  assert.deepEqual(rooms.join(id, 'client-cccc', 's3', 'Eve', true, true), { ok: false, error: 'full' });
  const again = rooms.join(id, 'client-aaaa', 's4', 'Ana', true, true);
  assert.ok(again.ok);
  assert.equal(again.participant.id, a.participant.id);
  assert.equal(again.replacedSocketId, 's1');
  assert.equal(rooms.state(id)!.participants.length, 2);
});

test('unknown rooms cannot be joined', () => {
  const { rooms } = setup();
  assert.deepEqual(rooms.join('doesNotExist1', 'client-aaaa', 's1', 'Ana', true, true), { ok: false, error: 'not_found' });
});

test('free rooms get one timed session, then a cooldown that blocks restarting the stream', () => {
  const { rooms, advance } = setup(60_000, 20_000);
  const { id } = rooms.create();
  const a = rooms.join(id, 'client-aaaa', 's1', 'Ana', true, true);
  assert.ok(a.ok);
  const pid = a.participant.id;
  assert.deepEqual(rooms.startStream(id, pid, { mode: 'screen', by: pid }), { ok: true });
  assert.equal(rooms.state(id)!.session.state, 'running');
  const firstEndsAt = rooms.state(id)!.session.endsAt;

  // Stopping and starting again does not reset the clock.
  rooms.stopStream(id, pid);
  advance(30_000);
  rooms.startStream(id, pid, { mode: 'screen', by: pid });
  assert.equal(rooms.state(id)!.session.endsAt, firstEndsAt);

  advance(31_000);
  assert.equal(rooms.state(id)!.session.state, 'cooldown');
  const locked = rooms.startStream(id, pid, { mode: 'screen', by: pid });
  assert.equal(locked.ok, false);
  assert.equal(!locked.ok && locked.error, 'session_locked');

  advance(20_000);
  assert.equal(rooms.state(id)!.session.state, 'idle');
  assert.deepEqual(rooms.startStream(id, pid, { mode: 'screen', by: pid }), { ok: true });
});

test('a Date Night Pass unlocks HD with no clock for 24 hours, and fulfilment is idempotent', () => {
  const { rooms, advance, events } = setup();
  const { id } = rooms.create();
  const a = rooms.join(id, 'client-aaaa', 's1', 'Ana', true, true);
  assert.ok(a.ok);
  rooms.startStream(id, a.participant.id, { mode: 'screen', by: a.participant.id });

  assert.equal(rooms.fulfill(id, 'cs_test_1', 'pass'), true);
  assert.equal(rooms.fulfill(id, 'cs_test_1', 'pass'), false, 'the same checkout must not apply twice');
  const state = rooms.state(id)!;
  assert.equal(state.entitlement.tier, 'pass');
  assert.equal(state.entitlement.quality, 'hd');
  assert.equal(state.entitlement.ads, false);
  assert.equal(state.session.state, 'idle');
  assert.equal(state.sparks, STARTER_SPARKS + 5);
  assert.ok(events.includes('upgraded:pass'));

  advance(24 * 3600_000 + 1);
  assert.equal(rooms.state(id)!.entitlement.tier, 'free');
});

test('Couples Pro follows the Stripe subscription status', () => {
  const { rooms } = setup();
  const record = rooms.create();
  rooms.fulfill(record.id, 'cs_test_pro', 'pro', { customerId: 'cus_1', subscriptionId: 'sub_1', status: 'active', cancelAtPeriodEnd: false });
  assert.equal(rooms.state(record.id)!.entitlement.tier, 'pro');
  assert.equal(rooms.state(record.id)!.entitlement.frames, true);
  rooms.updatePro(record, { status: 'past_due' });
  assert.equal(rooms.tier(record), 'pro', 'access is kept while Stripe retries the card');
  rooms.updatePro(record, { status: 'canceled' });
  assert.equal(rooms.tier(record), 'free');
});

test('gifts spend the shared wallet, respect a cooldown and cannot overdraw', () => {
  const { rooms, advance } = setup();
  const { id } = rooms.create();
  const a = rooms.join(id, 'client-aaaa', 's1', 'Ana', true, true);
  assert.ok(a.ok);
  const pid = a.participant.id;
  assert.deepEqual(rooms.sendGift(id, pid, 'fireworks'), { ok: true, sparks: STARTER_SPARKS - 3 });
  assert.equal((rooms.sendGift(id, pid, 'hearts') as { error?: string }).error, 'cooldown');
  advance(2_000);
  assert.equal((rooms.sendGift(id, pid, 'champagne') as { error?: string }).error, 'insufficient');
  assert.deepEqual(rooms.sendGift(id, pid, 'hearts'), { ok: true, sparks: 0 }, 'hearts are always free');
  assert.equal((rooms.sendGift(id, pid, 'nope') as { error?: string }).error, 'unknown_gift');
});

test('frames require Pro', () => {
  const { rooms } = setup();
  const { id } = rooms.create();
  const a = rooms.join(id, 'client-aaaa', 's1', 'Ana', true, true);
  assert.ok(a.ok);
  assert.deepEqual(rooms.setFrame(id, a.participant.id, 'rosegold'), { ok: false, error: 'pro_required' });
  assert.deepEqual(rooms.setFrame(id, a.participant.id, 'none'), { ok: true });
});

test('a partner who drops is held for the grace period, then removed', async () => {
  const { rooms, events } = setup();
  const { id } = rooms.create();
  const a = rooms.join(id, 'client-aaaa', 's1', 'Ana', true, true);
  const b = rooms.join(id, 'client-bbbb', 's2', 'Ben', true, true);
  assert.ok(a.ok && b.ok);
  rooms.disconnect(id, b.participant.id, 's2');
  assert.equal(rooms.state(id)!.participants.find((p) => p.id === b.participant.id)?.connected, false);
  await new Promise((r) => setTimeout(r, 80));
  assert.equal(rooms.state(id)!.participants.length, 1);
  assert.ok(events.includes('peer:left'));
});
