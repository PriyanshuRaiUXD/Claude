import crypto from 'node:crypto';

const ALPHABET = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** URL-safe random id without look-alike characters. 12 chars ≈ 70 bits: room links are unguessable. */
export function randomId(length = 12): string {
  const bytes = crypto.randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i++) out += ALPHABET[bytes[i]! % ALPHABET.length];
  return out;
}

export const ROOM_ID_RE = /^[a-zA-Z0-9]{8,32}$/;

export function sha256(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}
