import crypto from 'node:crypto';
import Stripe from 'stripe';
import { PLANS, PRODUCT_IDS, productInfo, type ProductId } from '../shared/catalog';
import { config } from './config';
import { randomId, sha256 } from './ids';
import type { Rooms } from './rooms';
import type { Store } from './store';

export class BillingError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export function isProductId(value: unknown): value is ProductId {
  return typeof value === 'string' && (PRODUCT_IDS as string[]).includes(value);
}

export interface CheckoutResult {
  url: string;
}

export interface VerifyResult {
  status: 'paid' | 'pending' | 'unpaid';
  product?: ProductId;
  /** One-time secret that lets this browser open the Stripe billing portal for the room's Pro plan. */
  manageToken?: string;
}

/**
 * All money flows through here. Entitlements are only ever granted from data that came from
 * Stripe's servers (a signed webhook, or a Checkout Session fetched with the secret key) — never
 * from anything a browser says. Demo mode replaces Stripe with a signed local token.
 */
export class Billing {
  readonly stripe: Stripe | null;
  /** Signs demo checkout tokens. Random per boot, so tokens die with the process. */
  private readonly demoSecret = crypto.randomBytes(32);

  constructor(
    private readonly rooms: Rooms,
    private readonly store: Store,
  ) {
    this.stripe = config.stripeSecretKey ? new Stripe(config.stripeSecretKey, { appInfo: { name: 'Loveseat', version: '1.0.0' } }) : null;
  }

  // --------------------------------------------------------------- checkout --

  async createCheckout(roomId: string, product: ProductId, origin: string): Promise<CheckoutResult> {
    const record = this.rooms.record(roomId);
    if (!record) throw new BillingError(404, 'Room not found');
    const tier = this.rooms.tier(record);
    if (product === 'pro' && tier === 'pro') throw new BillingError(409, 'This room already has Couples Pro');
    if (product === 'pass' && tier === 'pro') throw new BillingError(409, 'Couples Pro already includes everything in the pass');

    const base = config.appUrl ?? origin;

    if (config.billingMode === 'disabled') throw new BillingError(503, 'Payments are not configured on this server');
    if (config.billingMode === 'demo' || !this.stripe) {
      return { url: `${base}/checkout/demo?t=${encodeURIComponent(this.signDemo(roomId, product))}` };
    }

    const info = productInfo(product);
    const metadata = { roomId, product };
    // Checkout opens in its own tab so the call never drops; these pages confirm and close that tab.
    const successUrl = `${base}/checkout/done?room=${roomId}&session_id={CHECKOUT_SESSION_ID}`;
    const cancelUrl = `${base}/checkout/done?room=${roomId}&cancelled=1`;

    const params: Stripe.Checkout.SessionCreateParams =
      product === 'pro'
        ? {
            mode: 'subscription',
            line_items: [
              config.stripeProPriceId
                ? { price: config.stripeProPriceId, quantity: 1 }
                : {
                    quantity: 1,
                    price_data: {
                      currency: info.currency,
                      unit_amount: info.amount,
                      recurring: { interval: PLANS.pro.interval },
                      product_data: { name: info.name, description: info.description },
                    },
                  },
            ],
            subscription_data: { metadata },
          }
        : {
            mode: 'payment',
            customer_creation: 'if_required',
            line_items: [
              {
                quantity: 1,
                price_data: {
                  currency: info.currency,
                  unit_amount: info.amount,
                  product_data: { name: info.name, description: info.description },
                },
              },
            ],
            payment_intent_data: { metadata },
          };

    const session = await this.stripe.checkout.sessions.create({
      ...params,
      client_reference_id: roomId,
      metadata,
      allow_promotion_codes: true,
      success_url: successUrl,
      cancel_url: cancelUrl,
    });
    if (!session.url) throw new BillingError(502, 'Stripe did not return a checkout URL');
    return { url: session.url };
  }

  /**
   * Called by the success page. Webhooks are the primary path; this makes local development work
   * without the Stripe CLI and closes the gap when a webhook is slow. Both paths are idempotent.
   */
  async verifyCheckout(roomId: string, sessionId: string): Promise<VerifyResult> {
    if (!this.stripe) throw new BillingError(400, 'Stripe is not configured');
    if (!/^cs_[a-zA-Z0-9_]+$/.test(sessionId)) throw new BillingError(400, 'Invalid session id');
    const session = await this.stripe.checkout.sessions.retrieve(sessionId, { expand: ['subscription'] });
    if (session.metadata?.roomId !== roomId) throw new BillingError(403, 'This checkout belongs to another room');
    const product = session.metadata?.product;
    if (!isProductId(product)) throw new BillingError(400, 'Unknown product on checkout');

    if (session.status !== 'complete') return { status: 'unpaid', product };
    if (session.payment_status === 'unpaid') return { status: 'pending', product }; // e.g. bank debits settling

    await this.fulfillSession(session);

    const result: VerifyResult = { status: 'paid', product };
    const record = this.rooms.record(roomId);
    if (product === 'pro' && record?.pro) {
      // Possession of a completed session id proves this browser went through checkout.
      result.manageToken = this.issueManageToken(roomId);
    }
    return result;
  }

  async createPortal(roomId: string, manageToken: string, origin: string): Promise<{ url: string }> {
    const record = this.rooms.record(roomId);
    if (!record?.pro) throw new BillingError(404, 'This room has no subscription');
    const hash = sha256(manageToken);
    const ok = record.pro.manageTokenHashes.some((h) => h.length === hash.length && crypto.timingSafeEqual(Buffer.from(h), Buffer.from(hash)));
    if (!ok) throw new BillingError(403, 'Only the partner who subscribed can manage billing from this browser');
    const base = config.appUrl ?? origin;
    if (!this.stripe || record.pro.customerId.startsWith('demo_')) {
      return { url: `${base}/checkout/demo?manage=${encodeURIComponent(roomId)}` };
    }
    const portal = await this.stripe.billingPortal.sessions.create({ customer: record.pro.customerId, return_url: `${base}/r/${roomId}` });
    return { url: portal.url };
  }

  // ---------------------------------------------------------------- webhook --

  async handleWebhook(rawBody: Buffer, signature: string | undefined): Promise<void> {
    if (!this.stripe) throw new BillingError(400, 'Stripe is not configured');
    if (!config.stripeWebhookSecret) throw new BillingError(500, 'STRIPE_WEBHOOK_SECRET is not set');
    if (!signature) throw new BillingError(400, 'Missing Stripe-Signature header');

    let event: Stripe.Event;
    try {
      event = this.stripe.webhooks.constructEvent(rawBody, signature, config.stripeWebhookSecret);
    } catch (err) {
      throw new BillingError(400, `Webhook signature verification failed: ${(err as Error).message}`);
    }
    // Stripe delivers at least once; an event id we have already processed is acknowledged and skipped.
    if (!this.store.markEvent(event.id)) return;

    switch (event.type) {
      case 'checkout.session.completed':
      case 'checkout.session.async_payment_succeeded': {
        const session = event.data.object;
        if (session.payment_status === 'unpaid') return; // async methods: wait for async_payment_succeeded
        const full = session.mode === 'subscription' ? await this.stripe.checkout.sessions.retrieve(session.id, { expand: ['subscription'] }) : session;
        await this.fulfillSession(full);
        return;
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        const record = this.store.findBySubscription(sub.id) ?? this.rooms.record(sub.metadata?.roomId ?? '');
        if (!record?.pro || record.pro.subscriptionId !== sub.id) return; // checkout.session.completed creates the link
        this.rooms.updatePro(record, subscriptionPatch(sub));
        return;
      }
      case 'invoice.paid': {
        const invoice = event.data.object;
        const details = invoice.parent?.subscription_details;
        if (!details) return;
        const subscriptionId = typeof details.subscription === 'string' ? details.subscription : details.subscription.id;
        const record = this.store.findBySubscription(subscriptionId) ?? this.rooms.record(details.metadata?.roomId ?? '');
        if (!record || !invoice.id) return;
        if (this.store.markFulfilled(record, invoice.id)) this.rooms.addSparks(record, PLANS.pro.monthlySparks);
        return;
      }
      default:
        return;
    }
  }

  private async fulfillSession(session: Stripe.Checkout.Session): Promise<void> {
    const roomId = session.metadata?.roomId;
    const product = session.metadata?.product;
    if (!roomId || !isProductId(product)) {
      console.warn(`[billing] checkout ${session.id} has no Loveseat metadata — ignored`);
      return;
    }
    if (!this.rooms.record(roomId)) {
      console.error(`[billing] PAID checkout ${session.id} references unknown room ${roomId}. Refund or restore it manually.`);
      return;
    }
    if (product !== 'pro') {
      this.rooms.fulfill(roomId, session.id, product);
      return;
    }

    let sub = session.subscription;
    if (!sub) return;
    if (typeof sub === 'string') sub = await this.stripe!.subscriptions.retrieve(sub);
    const customerId = typeof session.customer === 'string' ? session.customer : (session.customer?.id ?? '');
    this.rooms.fulfill(roomId, session.id, 'pro', { customerId, subscriptionId: sub.id, ...subscriptionPatch(sub) });
  }

  // ------------------------------------------------------------------- demo --

  private signDemo(roomId: string, product: ProductId): string {
    const body = Buffer.from(JSON.stringify({ r: roomId, p: product, n: randomId(10), e: Date.now() + 30 * 60_000 })).toString('base64url');
    const mac = crypto.createHmac('sha256', this.demoSecret).update(body).digest('base64url');
    return `${body}.${mac}`;
  }

  private readDemo(token: string): { roomId: string; product: ProductId; nonce: string } {
    const [body, mac] = token.split('.');
    if (!body || !mac) throw new BillingError(400, 'Malformed demo checkout');
    const expected = crypto.createHmac('sha256', this.demoSecret).update(body).digest('base64url');
    if (mac.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(expected))) {
      throw new BillingError(400, 'This demo checkout is invalid or from a previous server run');
    }
    const data = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as { r: string; p: string; n: string; e: number };
    if (Date.now() > data.e) throw new BillingError(410, 'This demo checkout expired');
    if (!isProductId(data.p)) throw new BillingError(400, 'Unknown product');
    return { roomId: data.r, product: data.p, nonce: data.n };
  }

  describeDemo(token: string): { roomId: string; product: ReturnType<typeof productInfo> } {
    if (config.billingMode !== 'demo') throw new BillingError(404, 'Demo checkout is off');
    const { roomId, product } = this.readDemo(token);
    return { roomId, product: productInfo(product) };
  }

  completeDemo(token: string): VerifyResult & { roomId: string } {
    if (config.billingMode !== 'demo') throw new BillingError(404, 'Demo checkout is off');
    const { roomId, product, nonce } = this.readDemo(token);
    if (!this.rooms.record(roomId)) throw new BillingError(404, 'Room not found');
    const ref = `demo_${nonce}`;
    const fresh =
      product === 'pro'
        ? this.rooms.fulfill(roomId, ref, 'pro', {
            customerId: `demo_cus_${nonce}`,
            subscriptionId: `demo_sub_${nonce}`,
            status: 'active',
            currentPeriodEnd: Math.floor(Date.now() / 1000) + 30 * 24 * 3600,
            cancelAtPeriodEnd: false,
          })
        : this.rooms.fulfill(roomId, ref, product);
    const record = this.rooms.record(roomId)!;
    if (fresh && product === 'pro') this.rooms.addSparks(record, PLANS.pro.monthlySparks); // stands in for invoice.paid
    const result: VerifyResult & { roomId: string } = { roomId, status: 'paid', product };
    if (product === 'pro') result.manageToken = this.issueManageToken(roomId);
    return result;
  }

  /** Demo stand-in for the Stripe portal's "Cancel plan" button. */
  cancelDemo(roomId: string, manageToken: string): void {
    if (config.billingMode !== 'demo') throw new BillingError(404, 'Demo checkout is off');
    const record = this.rooms.record(roomId);
    if (!record?.pro || !record.pro.manageTokenHashes.includes(sha256(manageToken))) throw new BillingError(403, 'Not allowed');
    this.rooms.updatePro(record, { status: 'canceled' });
  }

  private issueManageToken(roomId: string): string {
    const record = this.rooms.record(roomId)!;
    const token = randomId(32);
    this.rooms.addManageToken(record, sha256(token));
    return token;
  }
}

function subscriptionPatch(sub: Stripe.Subscription): { status: string; currentPeriodEnd?: number; cancelAtPeriodEnd: boolean } {
  return {
    status: sub.status,
    currentPeriodEnd: sub.items.data[0]?.current_period_end,
    cancelAtPeriodEnd: sub.cancel_at_period_end,
  };
}
