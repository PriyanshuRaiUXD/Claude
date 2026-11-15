import type { Server as HttpServer } from 'node:http';
import { Server, type Socket } from 'socket.io';
import { z } from 'zod';
import type { ClientToServerEvents, ServerToClientEvents, SignalPayload } from '../shared/types';
import { config } from './config';
import { iceServersFor } from './ice';
import { ROOM_ID_RE } from './ids';
import type { Rooms } from './rooms';

interface SocketData {
  roomId?: string;
  participantId?: string;
  /** Token bucket for signaling messages. */
  tokens: number;
  refilledAt: number;
}

type IO = Server<ClientToServerEvents, ServerToClientEvents, Record<string, never>, SocketData>;
type ClientSocket = Socket<ClientToServerEvents, ServerToClientEvents, Record<string, never>, SocketData>;

const joinSchema = z.object({
  roomId: z.string().regex(ROOM_ID_RE),
  clientId: z.string().min(8).max(64),
  name: z.string().max(64),
  micOn: z.boolean(),
  camOn: z.boolean(),
  /** This page still holds a live screen capture (socket blip, not a reload). */
  sharing: z.boolean().optional(),
});

const signalSchema = z.object({
  description: z
    .object({ type: z.enum(['offer', 'answer', 'pranswer', 'rollback']), sdp: z.string().max(100_000).optional() })
    .optional(),
  candidate: z
    .object({
      candidate: z.string().max(2_000).optional(),
      sdpMid: z.string().max(64).nullable().optional(),
      sdpMLineIndex: z.number().int().min(0).max(64).nullable().optional(),
      usernameFragment: z.string().max(256).nullable().optional(),
    })
    .nullable()
    .optional(),
  meta: z.object({ cam: z.string().max(128), screen: z.string().max(128) }).optional(),
  rebuild: z.boolean().optional(),
});

const streamSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('screen') }),
  z.object({ mode: z.literal('url'), src: z.string().max(2048), position: z.number().min(0).optional() }),
]);

/** Signaling allowance per socket: bursts of 200, refilled at 50/second. ICE trickle is bursty; abuse is not. */
const BUCKET_SIZE = 200;
const BUCKET_RATE = 50;

function allow(socket: ClientSocket): boolean {
  const now = Date.now();
  const d = socket.data;
  d.tokens = Math.min(BUCKET_SIZE, d.tokens + ((now - d.refilledAt) / 1000) * BUCKET_RATE);
  d.refilledAt = now;
  if (d.tokens < 1) return false;
  d.tokens -= 1;
  return true;
}

function safeUrl(raw: string): string | null {
  try {
    const url = new URL(raw);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : null;
  } catch {
    return null;
  }
}

export function attachSockets(httpServer: HttpServer, rooms: Rooms): IO {
  const io: IO = new Server(httpServer, {
    maxHttpBufferSize: 256 * 1024,
    pingInterval: 10_000,
    pingTimeout: 8_000,
    // Same-origin in production; Vite proxies in development. Lock it down when APP_URL is known.
    cors: config.isProd && config.appUrl ? { origin: config.appUrl } : undefined,
  });

  rooms.attach({
    state: (roomId, state) => io.to(roomId).emit('room:state', state),
    toRoom: (roomId, event, payload, except) => (except ? io.to(roomId).except(except) : io.to(roomId)).emit(event, payload),
    gift: (roomId, play) => io.to(roomId).emit('gift:play', play),
    sessionWarning: (roomId, msLeft) => io.to(roomId).emit('session:warning', { msLeft }),
    sessionExpired: (roomId, cooldownEndsAt) => io.to(roomId).emit('session:expired', { cooldownEndsAt }),
    upgraded: (roomId, tier) => io.to(roomId).emit('entitlement:upgraded', { tier }),
    sparksAdded: (roomId, amount, sparks) => io.to(roomId).emit('sparks:added', { amount, sparks }),
    replaced: (socketId) => {
      const old = io.sockets.sockets.get(socketId);
      if (!old) return;
      old.emit('session:replaced');
      old.data.roomId = undefined;
      old.disconnect(true);
    },
  });

  io.on('connection', (socket) => {
    socket.data.tokens = BUCKET_SIZE;
    socket.data.refilledAt = Date.now();

    const inRoom = (): { roomId: string; participantId: string } | null =>
      socket.data.roomId && socket.data.participantId ? { roomId: socket.data.roomId, participantId: socket.data.participantId } : null;

    socket.on('room:join', (raw, ack) => {
      if (typeof ack !== 'function') return;
      const parsed = joinSchema.safeParse(raw);
      if (!parsed.success) return ack({ ok: false, error: 'invalid' });
      const { roomId, clientId, name, micOn, camOn, sharing = false } = parsed.data;

      // A socket that switches rooms leaves the old one cleanly.
      const prev = inRoom();
      if (prev && prev.roomId !== roomId) {
        socket.leave(prev.roomId);
        rooms.disconnect(prev.roomId, prev.participantId, socket.id);
      }

      const outcome = rooms.join(roomId, clientId, socket.id, name, micOn, camOn, sharing);
      if (!outcome.ok) return ack({ ok: false, error: outcome.error });

      if (outcome.replacedSocketId) rooms.attachReplaced(outcome.replacedSocketId);
      socket.data.roomId = roomId;
      socket.data.participantId = outcome.participant.id;
      socket.join(roomId);

      ack({
        ok: true,
        selfId: outcome.participant.id,
        state: rooms.state(roomId)!,
        iceServers: iceServersFor(outcome.participant.id),
        serverNow: Date.now(),
      });
      // The partner (if any) throws away its old peer connection and waits for a fresh negotiation.
      socket.to(roomId).emit('peer:joined', { id: outcome.participant.id });
      rooms.broadcast(roomId);
    });

    socket.on('signal', (raw) => {
      const here = inRoom();
      if (!here || !allow(socket)) return;
      const parsed = signalSchema.safeParse(raw);
      if (!parsed.success) return;
      // Two-seat rooms: everything goes to "the other one".
      socket.to(here.roomId).emit('signal', parsed.data as SignalPayload);
    });

    socket.on('media:state', (raw) => {
      const here = inRoom();
      if (!here || typeof raw?.micOn !== 'boolean' || typeof raw?.camOn !== 'boolean') return;
      rooms.setMedia(here.roomId, here.participantId, raw.micOn, raw.camOn);
    });

    socket.on('name:set', (raw) => {
      const here = inRoom();
      if (here && typeof raw?.name === 'string') rooms.setName(here.roomId, here.participantId, raw.name);
    });

    socket.on('stream:start', (raw, ack) => {
      if (typeof ack !== 'function') return;
      const here = inRoom();
      if (!here) return ack({ ok: false, error: 'not_in_room' });
      const parsed = streamSchema.safeParse(raw);
      if (!parsed.success) return ack({ ok: false, error: 'invalid_url' });
      if (parsed.data.mode === 'screen') {
        return ack(rooms.startStream(here.roomId, here.participantId, { mode: 'screen', by: here.participantId }));
      }
      const src = safeUrl(parsed.data.src);
      if (!src) return ack({ ok: false, error: 'invalid_url' });
      ack(
        rooms.startStream(here.roomId, here.participantId, {
          mode: 'url',
          by: here.participantId,
          url: { src, playing: false, position: parsed.data.position ?? 0, updatedAt: Date.now() },
        }),
      );
    });

    socket.on('stream:stop', () => {
      const here = inRoom();
      if (here) rooms.stopStream(here.roomId, here.participantId);
    });

    socket.on('url:control', (raw) => {
      const here = inRoom();
      if (!here || !allow(socket) || typeof raw?.playing !== 'boolean' || typeof raw?.position !== 'number') return;
      rooms.urlControl(here.roomId, here.participantId, raw.playing, raw.position);
    });

    socket.on('gift:send', (raw, ack) => {
      if (typeof ack !== 'function') return;
      const here = inRoom();
      if (!here) return ack({ ok: false, error: 'not_in_room' });
      ack(rooms.sendGift(here.roomId, here.participantId, String(raw?.giftId ?? '')));
    });

    socket.on('frame:set', (raw, ack) => {
      if (typeof ack !== 'function') return;
      const here = inRoom();
      if (!here) return ack({ ok: false, error: 'not_in_room' });
      ack(rooms.setFrame(here.roomId, here.participantId, String(raw?.frame ?? '')));
    });

    socket.on('time:sync', (ack) => {
      if (typeof ack === 'function') ack(Date.now());
    });

    socket.on('disconnect', () => {
      const here = inRoom();
      if (here) rooms.disconnect(here.roomId, here.participantId, socket.id);
    });
  });

  return io;
}
