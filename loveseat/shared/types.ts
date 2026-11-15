import type { Entitlement, FrameId, GiftId } from './catalog';

export interface Participant {
  id: string;
  name: string;
  micOn: boolean;
  camOn: boolean;
  /** False while the partner's socket is briefly reconnecting. */
  connected: boolean;
}

export interface UrlPlayback {
  src: string;
  playing: boolean;
  /** Playback position in seconds at `updatedAt`. */
  position: number;
  /** Server clock (epoch ms) when `position` was sampled. */
  updatedAt: number;
}

export type StreamState =
  | { mode: 'none' }
  | { mode: 'screen'; by: string }
  | { mode: 'url'; by: string; url: UrlPlayback };

export interface SessionInfo {
  /** idle: no free session running. running: clock is ticking. cooldown: free streaming is locked. */
  state: 'idle' | 'running' | 'cooldown';
  limitMs: number;
  endsAt?: number;
  cooldownEndsAt?: number;
}

export interface RoomState {
  id: string;
  participants: Participant[];
  entitlement: Entitlement;
  session: SessionInfo;
  stream: StreamState;
  sparks: number;
  frame: FrameId;
}

/** Tells the receiver which incoming MediaStream is the webcam and which is the shared screen. */
export interface MediaMeta {
  cam: string;
  screen: string;
}

export interface SignalPayload {
  description?: { type: 'offer' | 'answer' | 'pranswer' | 'rollback'; sdp?: string };
  candidate?: { candidate?: string; sdpMid?: string | null; sdpMLineIndex?: number | null; usernameFragment?: string | null } | null;
  meta?: MediaMeta;
  /** Ask the other side to throw away its peer connection and start clean. */
  rebuild?: boolean;
}

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

export type JoinError = 'not_found' | 'full' | 'invalid';

export type JoinResult =
  | { ok: true; selfId: string; state: RoomState; iceServers: IceServer[]; serverNow: number }
  | { ok: false; error: JoinError };

export type StreamStartResult =
  | { ok: true }
  | { ok: false; error: 'session_locked'; cooldownEndsAt: number }
  | { ok: false; error: 'busy' | 'invalid_url' | 'not_in_room' };

export type GiftResult =
  | { ok: true; sparks: number }
  | { ok: false; error: 'insufficient' | 'cooldown' | 'unknown_gift' | 'not_in_room'; sparks?: number };

export type FrameResult = { ok: true } | { ok: false; error: 'pro_required' | 'unknown_frame' | 'not_in_room' };

export interface GiftPlay {
  id: string;
  giftId: GiftId;
  from: string;
  fromName: string;
  /** Seeds the particle simulation so both screens draw the same show. */
  seed: number;
}

export interface ClientToServerEvents {
  'room:join': (
    payload: { roomId: string; clientId: string; name: string; micOn: boolean; camOn: boolean; sharing: boolean },
    ack: (result: JoinResult) => void,
  ) => void;
  signal: (payload: SignalPayload) => void;
  'media:state': (payload: { micOn: boolean; camOn: boolean }) => void;
  'name:set': (payload: { name: string }) => void;
  'stream:start': (payload: { mode: 'screen' } | { mode: 'url'; src: string; position?: number }, ack: (r: StreamStartResult) => void) => void;
  'stream:stop': () => void;
  'url:control': (payload: { playing: boolean; position: number }) => void;
  'gift:send': (payload: { giftId: string }, ack: (r: GiftResult) => void) => void;
  'frame:set': (payload: { frame: string }, ack: (r: FrameResult) => void) => void;
  'time:sync': (ack: (serverNow: number) => void) => void;
}

export interface ServerToClientEvents {
  'room:state': (state: RoomState) => void;
  'peer:joined': (payload: { id: string }) => void;
  'peer:left': (payload: { id: string }) => void;
  signal: (payload: SignalPayload) => void;
  'gift:play': (payload: GiftPlay) => void;
  'session:warning': (payload: { msLeft: number }) => void;
  'session:expired': (payload: { cooldownEndsAt: number }) => void;
  'entitlement:upgraded': (payload: { tier: 'pass' | 'pro' }) => void;
  'sparks:added': (payload: { amount: number; sparks: number }) => void;
  'session:replaced': () => void;
}

/** Shape of GET /api/config. */
export interface PublicConfig {
  billingMode: 'stripe' | 'demo' | 'disabled';
  freeSessionMs: number;
  freeCooldownMs: number;
  ads: {
    adsense: { client: string; slot: string } | null;
    house: HouseAd[];
  };
}

export interface HouseAd {
  id: string;
  sponsor: string;
  title: string;
  body: string;
  cta: string;
  /** Either an absolute https URL or an in-app action. */
  href: string;
}
