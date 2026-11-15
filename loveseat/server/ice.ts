import crypto from 'node:crypto';
import { config } from './config';
import type { IceServer } from '../shared/types';

/**
 * ICE servers handed to a browser when it joins a room.
 *
 * STUN alone connects most home networks. Roughly one connection in ten sits behind
 * symmetric NAT or a strict firewall and needs a TURN relay — configure one for production.
 */
export function iceServersFor(participantId: string): IceServer[] {
  const servers: IceServer[] = [...config.iceServers];
  const { urls, username, credential, secret } = config.turn;
  if (urls.length === 0) return servers;

  if (secret) {
    // coturn "REST API" auth: username = "<expiry>:<id>", credential = base64(HMAC-SHA1(secret, username)).
    const expiry = Math.floor(Date.now() / 1000) + 12 * 60 * 60;
    const user = `${expiry}:${participantId}`;
    const pass = crypto.createHmac('sha1', secret).update(user).digest('base64');
    servers.push({ urls, username: user, credential: pass });
  } else if (username && credential) {
    servers.push({ urls, username, credential });
  }
  return servers;
}
