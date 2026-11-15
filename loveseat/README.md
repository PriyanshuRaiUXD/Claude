# Loveseat

A private virtual living room for two. One partner opens a room link and shares any browser tab, window or screen (Netflix, YouTube, live sport, anything) with stereo system audio. Both webcams float over the stream as draggable picture-in-picture bubbles. Controls stay invisible until you move the mouse.

It makes money three ways, all built in: a **Couples Pro** subscription ($7.99/mo, covers both partners), a one-time **Date Night Pass** ($1.99 for 24 h), and **gift Sparks** for animated date-night gifts synced to both screens.

## Run it locally

Requires **Node.js 20.11+**. Use desktop Chrome or Edge for the full experience; tab audio capture is best there.

```bash
cd loveseat
npm install
cp .env.example .env      # optional — everything works without editing it
npm run dev
```

Open **http://localhost:5173** and click **Open our living room**. To be both partners on one machine, open the room link in a second tab or browser window. Each tab is its own person.

With no Stripe key, purchases go through a clearly labelled **demo checkout** (nothing is charged), so every paid flow can be tried immediately.

### Production build

```bash
npm run build
npm start                 # serves app + API on http://localhost:3001
```

`npm start` runs in production mode. **Without a Stripe key it refuses purchases** rather than giving them away. Set `ALLOW_DEMO_BILLING=true` only for a local demo.

### Real Stripe payments (test mode)

1. Put your test secret key in `.env`: `STRIPE_SECRET_KEY=sk_test_…`
2. Forward webhooks with the [Stripe CLI](https://docs.stripe.com/stripe-cli):
   ```bash
   stripe listen --forward-to localhost:3001/api/stripe/webhook
   ```
   Copy the printed `whsec_…` into `STRIPE_WEBHOOK_SECRET`, then restart `npm run dev`.
3. Pay with card `4242 4242 4242 4242`, any future date, any CVC.

No products need to be created in the Dashboard; prices are defined inline. For the **Manage subscription** button, save your Customer Portal settings once in the Dashboard (Settings → Billing → Customer portal).

In production, register a webhook endpoint at `https://YOUR_DOMAIN/api/stripe/webhook` for: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`.

### Tests

```bash
npm test          # server unit tests: seats, session clock, pass/pro, gifts, frames, reconnect
npm run typecheck
```

## How it works

| Piece | Choice | Why |
|---|---|---|
| Media | **WebRTC peer-to-peer** | Two people per room, so a mesh *is* one connection. Lowest latency, end-to-end encrypted, and no media server bill. |
| Signaling + room state | **Node + Express + Socket.IO** | Reconnection, rooms and acks built in; one process serves API, sockets and the built client. |
| Payments | **Stripe Checkout + signed webhooks** | Hosted, PCI-free card capture; entitlements only granted from Stripe-verified data. |
| Client | **React 19 + Vite + TypeScript** | Shared types between server and client (`shared/`), so prices, tiers and socket events can't drift. |
| Storage | **Atomic JSON file** behind a `Store` class | Zero setup locally. Swap the class for Postgres/Redis to scale out. |

```
loveseat/
├── shared/            catalog.ts (prices, tiers, gifts, frames) · types.ts (socket protocol)
├── server/
│   ├── index.ts       boot, shutdown
│   ├── app.ts         HTTP routes, CSP, rate limits, static client
│   ├── socket.ts      signaling relay, validation, per-socket rate limit
│   ├── rooms.ts       seats, reconnect grace, stream ownership, free-session clock, Sparks, frames
│   ├── billing.ts     Stripe Checkout, webhook, return-page verify, portal, demo checkout
│   ├── store.ts       durable room records + idempotency
│   ├── ice.ts         STUN/TURN (incl. coturn time-limited credentials)
│   └── rooms.test.ts
└── src/
    ├── lib/peer.ts    perfect-negotiation PeerConnection, stereo Opus, adaptive quality ladder
    ├── lib/media.ts   camera + screen capture constraints per tier
    ├── lib/gifts.ts   seeded canvas particle engine (same show on both screens)
    ├── pages/         Landing · Room · Checkout (Stripe return + demo)
    └── components/    CamBubble (PiP) · Controls (hover bar) · Lobby/AdSlot · UrlPlayer · UpgradeSheet …
```

**Quality.** Free rooms capture at 720p30; paid rooms at 1080p60 (camera and screen). Every 2 s the sender reads WebRTC stats. If the stream is bandwidth- or CPU-limited, it steps down a ladder (1080p60 → 1080p30 → 720p30 → 540p30 → 360p24), and it steps back up after sustained headroom. Only the ceiling moves; the call never drops. While a screen is shared, webcam bitrate is capped so the movie gets the bandwidth.

**Audio.** Screen audio is captured with echo cancellation, noise suppression and AGC **off** (they wreck music) and sent as stereo Opus at up to 256 kbps. When sharing a Chrome tab, its local playback is muted and the app plays it in sync with the preview, so the sharer's volume mixer works too.

**Keyboard:** `M` mic · `V` camera · `H` hide/show self-view · `F` fullscreen. Double-click a bubble to reset its position.

## Known limits

- **Quality gating is enforced by the client.** Media flows browser-to-browser, so a modified client could exceed 720p. Server-enforced quality would need an SFU (e.g. LiveKit/mediasoup) in the media path. The free-session clock, Sparks, frames and all purchases *are* server-enforced.
- **Rooms are anonymous.** Creating a fresh room resets the free clock. Accounts would close that loophole, at the cost of the "send one link" onboarding.
- **DRM services** (Netflix, Disney+, Prime) block capture of protected video in some browsers and OSes: the partner sees a black frame. That is the services' choice; no web app can bypass it. YouTube, Twitch, sport sites and local files work.
- **TURN is needed in production** for about 1 in 10 connections. Configure `TURN_*` (e.g. coturn, Cloudflare Calls, Twilio).
- **One server instance.** Room presence is in memory. Scale out with Redis (Socket.IO adapter) plus a database-backed `Store`.
