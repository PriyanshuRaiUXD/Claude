import { useState } from 'react';
import { PLANS, SPARK_PACKS, formatPrice, type ProductId, type Tier } from '../../shared/catalog';
import { openCheckout } from '../lib/api';
import { IconClose, IconHeart, IconSparkle } from './Icons';

export type UpgradeReason = 'manual' | 'expired' | 'warning' | 'quality' | 'frames' | 'sparks';

const HEADLINES: Record<UpgradeReason, { title: string; body: string }> = {
  manual: { title: 'Make movie night feel like the real thing', body: 'Both of you get everything — one purchase covers the room.' },
  expired: { title: 'Your free hour is up — the movie doesn’t have to be', body: 'You can still see and hear each other. Unlock the stream to keep watching.' },
  warning: { title: 'Five minutes left on your free hour', body: 'Upgrade now and the stream keeps going without a blip.' },
  quality: { title: 'Watch in true 1080p at 60fps', body: 'Free rooms stream at 720p/30. Go HD for crisp detail and smooth sport.' },
  frames: { title: 'Cozy frames come with Couples Pro', body: 'Rose gold, fireside, polaroid, neon diner and moonlight — for both screens.' },
  sparks: { title: 'Top up your gift Sparks', body: 'Sparks are shared by both of you. Hearts are always free.' },
};

interface Props {
  roomId: string;
  tier: Tier;
  reason: UpgradeReason;
  billingMode: 'stripe' | 'demo' | 'disabled';
  onClose: () => void;
  onNotice: (text: string) => void;
}

export function UpgradeSheet({ roomId, tier, reason, billingMode, onClose, onNotice }: Props) {
  const [busy, setBusy] = useState<ProductId | null>(null);
  const [error, setError] = useState<string | null>(null);
  const head = HEADLINES[reason];
  const showPlans = reason !== 'sparks' && tier !== 'pro';

  const buy = async (product: ProductId) => {
    setBusy(product);
    setError(null);
    try {
      const how = await openCheckout(roomId, product);
      if (how === 'opened') onNotice('Checkout opened in a new tab — your movie keeps playing here.');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={head.title} onClick={(e) => e.stopPropagation()}>
        <button className="sheet-close icon-btn" onClick={onClose} aria-label="Close">
          <IconClose />
        </button>
        <h2>{head.title}</h2>
        <p className="muted">{head.body}</p>
        {billingMode === 'demo' && <p className="demo-note">Demo mode: no Stripe key is configured, so checkout is simulated and nothing is charged.</p>}
        {billingMode === 'disabled' && <p className="demo-note">Payments are not configured on this server yet.</p>}

        {showPlans && (
          <div className="plans">
            <div className="plan plan-pass">
              <div className="plan-head">
                <span className="plan-name">{PLANS.pass.name}</span>
                <span className="plan-price">
                  {formatPrice(PLANS.pass.amount)} <small>once</small>
                </span>
              </div>
              <p className="plan-tag">{PLANS.pass.tagline}</p>
              <ul>
                {PLANS.pass.perks.map((p) => (
                  <li key={p}>{p}</li>
                ))}
              </ul>
              <button className="btn btn-soft" disabled={!!busy || billingMode === 'disabled'} onClick={() => buy('pass')}>
                {busy === 'pass' ? 'Opening…' : tier === 'pass' ? 'Add another 24 hours' : 'Unlock tonight'}
              </button>
            </div>
            <div className="plan plan-pro">
              <span className="plan-badge">
                <IconHeart width={12} height={12} /> Covers both of you
              </span>
              <div className="plan-head">
                <span className="plan-name">{PLANS.pro.name}</span>
                <span className="plan-price">
                  {formatPrice(PLANS.pro.amount)} <small>/ month</small>
                </span>
              </div>
              <p className="plan-tag">{PLANS.pro.tagline}</p>
              <ul>
                {PLANS.pro.perks.map((p) => (
                  <li key={p}>{p}</li>
                ))}
              </ul>
              <button className="btn btn-primary" disabled={!!busy || billingMode === 'disabled'} onClick={() => buy('pro')}>
                {busy === 'pro' ? 'Opening…' : 'Go Couples Pro'}
              </button>
              <small className="muted">Cancel anytime.</small>
            </div>
          </div>
        )}

        <div className="packs">
          <h3>
            <IconSparkle width={16} height={16} /> Gift Sparks
          </h3>
          <div className="packs-row">
            {SPARK_PACKS.map((pack) => (
              <button key={pack.id} className="pack" disabled={!!busy || billingMode === 'disabled'} onClick={() => buy(pack.id)}>
                {pack.badge && <span className="pack-badge">{pack.badge}</span>}
                <strong>{pack.sparks} ✦</strong>
                <span>{busy === pack.id ? 'Opening…' : formatPrice(pack.amount)}</span>
              </button>
            ))}
          </div>
        </div>
        {error && <p className="error">{error}</p>}
      </div>
    </div>
  );
}
