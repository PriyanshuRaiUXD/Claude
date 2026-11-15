/** Storage can throw (private mode, blocked site data). Every access goes through these. */
function wrap(kind: 'local' | 'session') {
  const area = (): Storage | null => {
    try {
      return kind === 'local' ? window.localStorage : window.sessionStorage;
    } catch {
      return null;
    }
  };
  return {
    get(key: string): string | null {
      try {
        return area()?.getItem(key) ?? null;
      } catch {
        return null;
      }
    },
    set(key: string, value: string): void {
      try {
        area()?.setItem(key, value);
      } catch {
        /* ignore */
      }
    },
    remove(key: string): void {
      try {
        area()?.removeItem(key);
      } catch {
        /* ignore */
      }
    },
    json<T>(key: string, fallback: T): T {
      const raw = this.get(key);
      if (!raw) return fallback;
      try {
        return JSON.parse(raw) as T;
      } catch {
        return fallback;
      }
    },
  };
}

export const local = wrap('local');
export const session = wrap('session');

const memoryIds = new Map<string, string>();

function randomToken(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Identifies this tab to the server so a reload or network blip reclaims the same seat.
 * Per tab (sessionStorage), so two tabs on one machine are two people — handy for testing.
 */
export function clientId(roomId: string): string {
  const key = `loveseat:client:${roomId}`;
  const existing = session.get(key) ?? memoryIds.get(key);
  if (existing) return existing;
  const id = randomToken();
  session.set(key, id);
  memoryIds.set(key, id);
  return id;
}

/** True when this tab already holds (or held) a seat in the room — e.g. after a reload. */
export function hasSeat(roomId: string): boolean {
  return !!(session.get(`loveseat:client:${roomId}`) ?? memoryIds.get(`loveseat:client:${roomId}`));
}

export const prefs = {
  name: () => local.get('loveseat:name') ?? '',
  setName: (v: string) => local.set('loveseat:name', v),
  media: () => local.json('loveseat:media', { micOn: true, camOn: true }),
  setMedia: (v: { micOn: boolean; camOn: boolean }) => local.set('loveseat:media', JSON.stringify(v)),
  mixer: () => local.json('loveseat:mixer', { stream: 1, voice: 0.85 }),
  setMixer: (v: { stream: number; voice: number }) => local.set('loveseat:mixer', JSON.stringify(v)),
  selfHidden: () => local.get('loveseat:selfHidden') === '1',
  setSelfHidden: (v: boolean) => local.set('loveseat:selfHidden', v ? '1' : '0'),
  bubbles: () => local.json<Record<string, BubbleRect>>('loveseat:bubbles', {}),
  setBubbles: (v: Record<string, BubbleRect>) => local.set('loveseat:bubbles', JSON.stringify(v)),
  manageToken: (roomId: string) => local.get(`loveseat:manage:${roomId}`),
  setManageToken: (roomId: string, token: string) => local.set(`loveseat:manage:${roomId}`, token),
};

/** Bubble geometry as fractions of the viewport, so it survives window resizes. */
export interface BubbleRect {
  x: number;
  y: number;
  w: number;
}
