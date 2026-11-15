import { io, type Socket } from 'socket.io-client';
import type { ClientToServerEvents, ServerToClientEvents } from '../../shared/types';

export type RoomSocket = Socket<ServerToClientEvents, ClientToServerEvents>;

export function connectSocket(): RoomSocket {
  return io({
    path: '/socket.io',
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionDelay: 500,
    reconnectionDelayMax: 4000,
  });
}

/** Estimates server clock offset so synced playback agrees on "now" across both screens. */
export class ServerClock {
  private offset = 0;
  private bestRtt = Infinity;

  seed(serverNow: number): void {
    this.offset = serverNow - Date.now();
  }

  now(): number {
    return Date.now() + this.offset;
  }

  async refine(socket: RoomSocket, samples = 5): Promise<void> {
    for (let i = 0; i < samples; i++) {
      const sent = Date.now();
      const serverNow = await new Promise<number | null>((resolve) => {
        const timer = setTimeout(() => resolve(null), 2000);
        socket.emit('time:sync', (t) => {
          clearTimeout(timer);
          resolve(t);
        });
      });
      if (serverNow === null) continue;
      const rtt = Date.now() - sent;
      if (rtt < this.bestRtt) {
        this.bestRtt = rtt;
        this.offset = serverNow + rtt / 2 - Date.now();
      }
    }
  }
}
