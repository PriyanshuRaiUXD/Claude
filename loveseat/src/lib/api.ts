import type { ProductId, ProductInfo, Tier } from '../../shared/catalog';
import type { PublicConfig } from '../../shared/types';

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
  });
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  if (!res.ok) throw new ApiError(res.status, body.error ?? `Request failed (${res.status})`);
  return body as T;
}

export interface VerifyResult {
  status: 'paid' | 'pending' | 'unpaid';
  product?: ProductId;
  manageToken?: string;
}

export const api = {
  config: () => request<PublicConfig>('/api/config'),
  createRoom: () => request<{ id: string }>('/api/rooms', { method: 'POST' }),
  room: (id: string) => request<{ id: string; tier: Tier; participants: number; full: boolean }>(`/api/rooms/${encodeURIComponent(id)}`),
  checkout: (roomId: string, product: ProductId) =>
    request<{ url: string }>('/api/checkout', { method: 'POST', body: JSON.stringify({ roomId, product }) }),
  verify: (roomId: string, sessionId: string) =>
    request<VerifyResult>(`/api/checkout/verify?roomId=${encodeURIComponent(roomId)}&session_id=${encodeURIComponent(sessionId)}`),
  portal: (roomId: string, manageToken: string) =>
    request<{ url: string }>('/api/billing/portal', { method: 'POST', body: JSON.stringify({ roomId, manageToken }) }),
  demoDescribe: (t: string) => request<{ roomId: string; product: ProductInfo }>(`/api/demo/checkout?t=${encodeURIComponent(t)}`),
  demoComplete: (t: string) => request<VerifyResult & { roomId: string }>('/api/demo/complete', { method: 'POST', body: JSON.stringify({ t }) }),
  demoCancel: (roomId: string, manageToken: string) =>
    request<{ ok: true }>('/api/demo/cancel', { method: 'POST', body: JSON.stringify({ roomId, manageToken }) }),
};

let configPromise: Promise<PublicConfig> | null = null;
export function loadConfig(): Promise<PublicConfig> {
  configPromise ??= api.config().catch((err) => {
    configPromise = null;
    throw err;
  });
  return configPromise;
}

/**
 * Opens Stripe Checkout in a new tab so the call and the movie keep running in this one.
 * The tab is opened synchronously (inside the click) so popup blockers allow it.
 */
export async function openCheckout(roomId: string, product: ProductId): Promise<'opened' | 'redirected'> {
  const tab = window.open('', '_blank');
  try {
    const { url } = await api.checkout(roomId, product);
    if (tab && !tab.closed) {
      tab.location.href = url;
      return 'opened';
    }
    window.location.href = url;
    return 'redirected';
  } catch (err) {
    tab?.close();
    throw err;
  }
}
