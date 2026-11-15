import { useEffect, useMemo, useRef } from 'react';
import type { PublicConfig } from '../../shared/types';

declare global {
  interface Window {
    adsbygoogle?: unknown[];
  }
}

let adsenseLoaded = false;

/**
 * Lobby-only ad. Real ads come from Google AdSense when ADSENSE_CLIENT/ADSENSE_SLOT are set;
 * otherwise rotating "house ads" (upsells, or sponsor cards from ADS_FILE) fill the slot.
 * It never renders during a stream.
 */
export function AdSlot({ ads, onAction }: { ads: PublicConfig['ads']; onAction: (action: string) => void }) {
  const adRef = useRef<HTMLModElement>(null);
  const house = useMemo(() => ads.house[Math.floor(Math.random() * ads.house.length)], [ads.house]);

  useEffect(() => {
    if (!ads.adsense) return;
    if (!adsenseLoaded) {
      adsenseLoaded = true;
      const s = document.createElement('script');
      s.async = true;
      s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${encodeURIComponent(ads.adsense.client)}`;
      s.crossOrigin = 'anonymous';
      document.head.appendChild(s);
    }
    try {
      (window.adsbygoogle = window.adsbygoogle || []).push({});
    } catch {
      /* blocked by an ad blocker: fine */
    }
  }, [ads.adsense]);

  if (ads.adsense) {
    return (
      <div className="adslot">
        <span className="adslot-label">Advertisement</span>
        <ins
          ref={adRef}
          className="adsbygoogle"
          style={{ display: 'block', minHeight: 90 }}
          data-ad-client={ads.adsense.client}
          data-ad-slot={ads.adsense.slot}
          data-ad-format="auto"
          data-full-width-responsive="true"
        />
      </div>
    );
  }
  if (!house) return null;
  const isAction = house.href.startsWith('action:');
  return (
    <div className="adslot adslot-house">
      <span className="adslot-label">{house.sponsor === 'Loveseat' ? 'From Loveseat' : `Sponsored · ${house.sponsor}`}</span>
      <strong>{house.title}</strong>
      <p>{house.body}</p>
      {isAction ? (
        <button className="btn btn-soft" onClick={() => onAction(house.href.slice('action:'.length))}>
          {house.cta}
        </button>
      ) : (
        <a className="btn btn-soft" href={house.href} target="_blank" rel="noopener noreferrer sponsored">
          {house.cta}
        </a>
      )}
    </div>
  );
}
