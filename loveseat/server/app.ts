import fs from 'node:fs';
import path from 'node:path';
import express, { type NextFunction, type Request, type Response } from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import { z } from 'zod';
import type { PublicConfig } from '../shared/types';
import { Billing, BillingError, isProductId } from './billing';
import { config } from './config';
import { ROOM_ID_RE } from './ids';
import type { Rooms } from './rooms';

function originOf(req: Request): string {
  return `${req.protocol}://${req.get('host')}`;
}

/** Wrap async handlers so a rejected promise reaches the error middleware (and never crashes the process). */
const route =
  (fn: (req: Request, res: Response) => Promise<unknown> | unknown) =>
  (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res)).catch(next);
  };

export function createApp(rooms: Rooms, billing: Billing): express.Express {
  const app = express();
  app.disable('x-powered-by');
  if (config.trustProxy > 0) app.set('trust proxy', config.trustProxy);

  const adsense = config.ads.adsense !== null;
  app.use(
    helmet({
      contentSecurityPolicy: {
        useDefaults: true,
        directives: {
          'script-src': ["'self'", ...(adsense ? ['https://pagead2.googlesyndication.com', 'https://*.googlesyndication.com', 'https://*.doubleclick.net', 'https://*.google.com'] : [])],
          'connect-src': ["'self'", 'https:', 'wss:'],
          // The URL player streams arbitrary public videos (and HLS segments as blobs).
          'media-src': ["'self'", 'https:', 'http:', 'blob:', 'data:'],
          'img-src': ["'self'", 'data:', 'blob:', 'https:'],
          'frame-src': adsense ? ['https://*.googlesyndication.com', 'https://*.doubleclick.net', 'https://*.google.com'] : ["'none'"],
          'worker-src': ["'self'", 'blob:'],
          // Off: it would break plain-http LAN testing and http:// video links. Terminate TLS at your proxy and send HSTS there.
          'upgrade-insecure-requests': null,
        },
      },
      crossOriginEmbedderPolicy: false,
      // Camera, microphone, screen capture and fullscreen for this origin only.
      permittedCrossDomainPolicies: false,
    }),
  );
  app.use((_req, res, next) => {
    res.setHeader('Permissions-Policy', 'camera=(self), microphone=(self), display-capture=(self), fullscreen=(self)');
    next();
  });

  // Stripe needs the exact bytes it signed, so this route is registered before the JSON parser.
  app.post(
    '/api/stripe/webhook',
    express.raw({ type: 'application/json', limit: '1mb' }),
    route(async (req, res) => {
      await billing.handleWebhook(req.body as Buffer, req.get('stripe-signature'));
      res.json({ received: true });
    }),
  );

  app.use(express.json({ limit: '16kb' }));

  const createLimiter = rateLimit({ windowMs: 60_000, limit: 20, standardHeaders: 'draft-8', legacyHeaders: false });
  const billingLimiter = rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: 'draft-8', legacyHeaders: false });

  app.get('/api/health', (_req, res) => {
    res.json({ ok: true, billing: config.billingMode, uptime: Math.round(process.uptime()) });
  });

  app.get('/api/config', (_req, res) => {
    const body: PublicConfig = {
      billingMode: config.billingMode,
      freeSessionMs: config.freeSessionMs,
      freeCooldownMs: config.freeCooldownMs,
      ads: config.ads,
    };
    res.json(body);
  });

  app.post('/api/rooms', createLimiter, (_req, res) => {
    const record = rooms.create();
    res.status(201).json({ id: record.id });
  });

  app.get('/api/rooms/:id', (req, res) => {
    const id = String(req.params.id);
    const record = ROOM_ID_RE.test(id) ? rooms.record(id) : undefined;
    if (!record) return res.status(404).json({ error: 'not_found' });
    // Advisory only (the socket join is authoritative). Seats in reconnect grace don't count, so a reload isn't told "full".
    res.json({ id, tier: rooms.tier(record), participants: rooms.participantCount(id), full: rooms.connectedCount(id) >= 2 });
  });

  const checkoutSchema = z.object({ roomId: z.string().regex(ROOM_ID_RE), product: z.string() });
  app.post(
    '/api/checkout',
    billingLimiter,
    route(async (req, res) => {
      const body = checkoutSchema.safeParse(req.body);
      if (!body.success || !isProductId(body.data.product)) return res.status(400).json({ error: 'Invalid checkout request' });
      res.json(await billing.createCheckout(body.data.roomId, body.data.product, originOf(req)));
    }),
  );

  app.get(
    '/api/checkout/verify',
    billingLimiter,
    route(async (req, res) => {
      const roomId = String(req.query.roomId ?? '');
      const sessionId = String(req.query.session_id ?? '');
      if (!ROOM_ID_RE.test(roomId)) return res.status(400).json({ error: 'Invalid room' });
      res.json(await billing.verifyCheckout(roomId, sessionId));
    }),
  );

  const portalSchema = z.object({ roomId: z.string().regex(ROOM_ID_RE), manageToken: z.string().min(16).max(128) });
  app.post(
    '/api/billing/portal',
    billingLimiter,
    route(async (req, res) => {
      const body = portalSchema.safeParse(req.body);
      if (!body.success) return res.status(400).json({ error: 'Invalid request' });
      res.json(await billing.createPortal(body.data.roomId, body.data.manageToken, originOf(req)));
    }),
  );

  // Demo checkout: only reachable when no Stripe key is configured (see config.billingMode).
  app.get('/api/demo/checkout', (req, res) => {
    res.json(billing.describeDemo(String(req.query.t ?? '')));
  });
  app.post('/api/demo/complete', billingLimiter, (req, res) => {
    res.json(billing.completeDemo(String(req.body?.t ?? '')));
  });
  app.post('/api/demo/cancel', billingLimiter, (req, res) => {
    const body = portalSchema.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'Invalid request' });
    billing.cancelDemo(body.data.roomId, body.data.manageToken);
    res.json({ ok: true });
  });

  app.use('/api', (_req, res) => res.status(404).json({ error: 'Not found' }));

  // Production: serve the built client and let the SPA handle /r/:id and /checkout/*.
  const clientDir = path.resolve('dist/client');
  if (fs.existsSync(path.join(clientDir, 'index.html'))) {
    app.use(express.static(clientDir, { index: false, maxAge: '1y', immutable: true, setHeaders: noCacheHtml }));
    app.get(/^\/(?!api\/|socket\.io\/).*/, (_req, res) => {
      res.setHeader('Cache-Control', 'no-cache');
      res.sendFile(path.join(clientDir, 'index.html'));
    });
  } else if (!config.isProd) {
    app.get('/', (_req, res) => res.type('text').send('Loveseat API is running. Open the app at http://localhost:5173'));
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof BillingError) return res.status(err.status).json({ error: err.message });
    const stripeMessage = (err as { type?: string; message?: string })?.type?.startsWith('Stripe') ? (err as Error).message : null;
    console.error('[http]', err);
    res.status(stripeMessage ? 502 : 500).json({ error: stripeMessage ?? 'Something went wrong' });
  });

  return app;
}

function noCacheHtml(res: Response, filePath: string): void {
  if (filePath.endsWith('.html')) res.setHeader('Cache-Control', 'no-cache');
}
