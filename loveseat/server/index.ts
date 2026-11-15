import http from 'node:http';
import { createApp } from './app';
import { Billing } from './billing';
import { config } from './config';
import { Rooms } from './rooms';
import { attachSockets } from './socket';
import { Store } from './store';

const store = new Store(config.dataDir);
const rooms = new Rooms(store, {
  freeSessionMs: config.freeSessionMs,
  freeCooldownMs: config.freeCooldownMs,
  reconnectGraceMs: config.reconnectGraceMs,
});
const billing = new Billing(rooms, store);
const app = createApp(rooms, billing);
const server = http.createServer(app);
const io = attachSockets(server, rooms);

if (config.isProd && !config.appUrl) {
  console.warn('[config] APP_URL is not set. Stripe redirect URLs will use the request Host header — set APP_URL in production.');
}
if (config.billingMode === 'stripe' && !config.stripeWebhookSecret) {
  console.warn('[config] STRIPE_WEBHOOK_SECRET is not set. Purchases still unlock via the return page, but renewals and cancellations will not sync.');
}
if (config.turn.urls.length === 0 && config.isProd) {
  console.warn('[config] No TURN server configured. Partners behind strict NATs or corporate firewalls will not connect.');
}

// Never-paid rooms nobody has opened in 30 days are forgotten.
const pruneTimer = setInterval(() => store.prune(30 * 24 * 3600_000), 6 * 3600_000);
pruneTimer.unref();

server.listen(config.port, () => {
  const mode = { stripe: 'Stripe', demo: 'DEMO (no Stripe key — simulated checkout, no money moves)', disabled: 'DISABLED' }[config.billingMode];
  console.log(`\n  ♥ Loveseat server on http://localhost:${config.port}`);
  console.log(`    billing: ${mode}`);
  const dur = (ms: number) => (ms >= 60_000 ? `${Math.round(ms / 60_000)} min` : `${Math.round(ms / 1000)} s`);
  console.log(`    free session: ${dur(config.freeSessionMs)}, cooldown ${dur(config.freeCooldownMs)}`);
  if (!config.isProd) console.log('    app (dev): http://localhost:5173\n');
});

let closing = false;
function shutdown(signal: string): void {
  if (closing) return;
  closing = true;
  console.log(`\n[loveseat] ${signal} — saving and shutting down`);
  store.flush();
  io.close();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
