import { PLANS, formatPrice } from '../../shared/catalog';
import type { Participant, PublicConfig, RoomState } from '../../shared/types';
import { canShareScreen } from '../lib/media';
import { AdSlot } from './AdSlot';
import { IconFilm, IconLink, IconScreen } from './Icons';

interface Props {
  state: RoomState;
  partner: Participant | null;
  config: PublicConfig;
  cooldownLeft: number | null;
  onShare: () => void;
  onUrl: () => void;
  onCopyLink: () => void;
  onAction: (action: string) => void;
}

function mins(ms: number): string {
  const m = Math.ceil(ms / 60_000);
  return `${m} minute${m === 1 ? '' : 's'}`;
}

/** Pre-stream "waiting room": who's here, what to watch, and (free rooms only) the lobby ad. */
export function Lobby({ state, partner, config, cooldownLeft, onShare, onUrl, onCopyLink, onAction }: Props) {
  const { entitlement } = state;
  const locked = cooldownLeft !== null && cooldownLeft > 0;
  return (
    <div className="lobby">
      <div className="lobby-card">
        <p className="lobby-kicker">{entitlement.tier === 'free' ? 'Free room · 720p' : entitlement.tier === 'pass' ? 'Date Night Pass · 1080p60' : 'Couples Pro · 1080p60'}</p>
        {partner ? (
          <h1>
            {partner.name} is {partner.connected ? 'here' : 'reconnecting'} <span className="heart">♥</span>
          </h1>
        ) : (
          <>
            <h1>Waiting for your person</h1>
            <p className="muted">Send them the room link. It's private — only someone with the link can join, and only two people fit.</p>
          </>
        )}

        <button className="btn btn-ghost lobby-invite" onClick={onCopyLink}>
          <IconLink width={18} height={18} /> Copy invite link
        </button>

        {locked ? (
          <div className="lobby-locked">
            <strong>Your free hour is used up.</strong>
            <p className="muted">Free streaming unlocks again in {mins(cooldownLeft)}. Your cameras and mics still work.</p>
            <button className="btn btn-primary" onClick={() => onAction('pass')}>
              Keep watching now — {formatPrice(PLANS.pass.amount)} tonight
            </button>
          </div>
        ) : (
          <div className="lobby-actions">
            <button className="btn btn-primary btn-lg" onClick={onShare} disabled={!canShareScreen}>
              <IconScreen /> Share a tab or screen
            </button>
            <button className="btn btn-soft btn-lg" onClick={onUrl}>
              <IconFilm /> Play a video link
            </button>
            {!canShareScreen && <p className="muted small">Sharing needs a desktop browser. You can still watch what your partner shares.</p>}
            {canShareScreen && <p className="muted small">Tip: pick a <b>Chrome tab</b> and tick “Share tab audio” for crisp stereo sound.</p>}
          </div>
        )}

        {entitlement.tier === 'free' && !locked && (
          <p className="muted small">Free rooms get {mins(config.freeSessionMs)} of streaming per session.</p>
        )}
      </div>
      {entitlement.ads && <AdSlot ads={config.ads} onAction={onAction} />}
    </div>
  );
}
