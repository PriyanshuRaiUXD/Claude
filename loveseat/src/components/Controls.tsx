import { useEffect, useRef, useState, type ReactNode } from 'react';
import { FRAMES, GIFTS, type FrameId, type GiftId, type Tier } from '../../shared/catalog';
import {
  IconCam,
  IconCamOff,
  IconClose,
  IconExitFull,
  IconEye,
  IconEyeOff,
  IconFilm,
  IconFull,
  IconGift,
  IconLink,
  IconLock,
  IconMic,
  IconMicOff,
  IconMixer,
  IconMore,
  IconScreen,
  IconStop,
  IconSwitch,
} from './Icons';

type Panel = 'mixer' | 'gifts' | 'more' | null;

export interface ControlsProps {
  visible: boolean;
  onHold: (hold: boolean) => void;
  // stream
  streamMode: 'none' | 'screen' | 'url';
  iAmSharing: boolean;
  canShare: boolean;
  onShare: () => void;
  onSwitchSource: () => void;
  onStopStream: () => void;
  onPlayUrl: () => void;
  // devices
  micOn: boolean;
  camOn: boolean;
  onToggleMic: () => void;
  onToggleCam: () => void;
  selfHidden: boolean;
  onToggleSelf: () => void;
  // mixer
  streamVolume: number;
  voiceVolume: number;
  onMixer: (v: { stream: number; voice: number }) => void;
  // gifts
  sparks: number;
  onGift: (id: GiftId) => void;
  onBuySparks: () => void;
  // room
  fullscreen: boolean;
  onFullscreen: () => void;
  onCopyLink: () => void;
  tier: Tier;
  frame: FrameId;
  onFrame: (id: FrameId) => void;
  onUpgrade: () => void;
  onManageBilling: (() => void) | null;
  onLeave: () => void;
}

function Btn({ label, onClick, active, danger, children, kbd }: { label: string; onClick: () => void; active?: boolean; danger?: boolean; children: ReactNode; kbd?: string }) {
  return (
    <button className={`ctl ${active ? 'is-active' : ''} ${danger ? 'is-danger' : ''}`} onClick={onClick} aria-label={label} aria-pressed={active}>
      {children}
      <span className="ctl-tip">
        {label}
        {kbd && <kbd>{kbd}</kbd>}
      </span>
    </button>
  );
}

/** Cinema-mode control bar: invisible until the pointer moves, gone again after 3s of stillness. */
export function Controls(p: ControlsProps) {
  const [panel, setPanel] = useState<Panel>(null);
  const [hovered, setHovered] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const { onHold } = p;

  useEffect(() => onHold(panel !== null || hovered), [panel, hovered, onHold]);

  useEffect(() => {
    if (!panel) return;
    const close = (e: PointerEvent) => {
      if (root.current && !root.current.contains(e.target as Node)) setPanel(null);
    };
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && setPanel(null);
    window.addEventListener('pointerdown', close);
    window.addEventListener('keydown', esc);
    return () => {
      window.removeEventListener('pointerdown', close);
      window.removeEventListener('keydown', esc);
    };
  }, [panel]);

  const toggle = (next: Panel) => setPanel((cur) => (cur === next ? null : next));

  return (
    <div
      ref={root}
      className={`controls ${p.visible || panel ? 'is-visible' : ''}`}
      onPointerEnter={() => setHovered(true)}
      onPointerLeave={() => setHovered(false)}
    >
      {panel === 'mixer' && (
        <div className="panel panel-mixer">
          <h4>Volume mixer</h4>
          <label>
            <span>Movie / stream</span>
            <input type="range" min={0} max={1} step={0.01} value={p.streamVolume} onChange={(e) => p.onMixer({ stream: Number(e.target.value), voice: p.voiceVolume })} />
            <output>{Math.round(p.streamVolume * 100)}</output>
          </label>
          <label>
            <span>Partner's voice</span>
            <input type="range" min={0} max={1} step={0.01} value={p.voiceVolume} onChange={(e) => p.onMixer({ stream: p.streamVolume, voice: Number(e.target.value) })} />
            <output>{Math.round(p.voiceVolume * 100)}</output>
          </label>
          {p.iAmSharing && <p className="muted small">You're sharing. If you shared a whole screen or window, its sound plays from your computer directly.</p>}
        </div>
      )}

      {panel === 'gifts' && (
        <div className="panel panel-gifts">
          <div className="panel-row">
            <h4>Send a little something</h4>
            <button className="sparks-chip" onClick={p.onBuySparks}>
              {p.sparks} ✦ <span>Get more</span>
            </button>
          </div>
          <div className="gift-grid">
            {GIFTS.map((g) => {
              const short = g.cost > p.sparks;
              return (
                <button key={g.id} className={`gift ${short ? 'is-short' : ''}`} onClick={() => (short ? p.onBuySparks() : p.onGift(g.id))} title={g.blurb}>
                  <span className="gift-emoji">{g.emoji}</span>
                  <span className="gift-name">{g.name}</span>
                  <span className="gift-cost">{g.cost === 0 ? 'Free' : `${g.cost} ✦`}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {panel === 'more' && (
        <div className="panel panel-more">
          <h4>Room frame {p.tier !== 'pro' && <span className="pro-chip">Pro</span>}</h4>
          <div className="frame-grid">
            {FRAMES.map((f) => {
              const locked = f.pro && p.tier !== 'pro';
              return (
                <button key={f.id} className={`frame-swatch swatch-${f.id} ${p.frame === f.id ? 'is-current' : ''}`} onClick={() => (locked ? p.onUpgrade() : p.onFrame(f.id))}>
                  <span className="swatch-preview" />
                  <span>
                    {locked && <IconLock width={12} height={12} />} {f.name}
                  </span>
                </button>
              );
            })}
          </div>
          <div className="more-actions">
            {p.tier !== 'pro' && (
              <button className="btn btn-primary" onClick={p.onUpgrade}>
                {p.tier === 'pass' ? 'Go Couples Pro' : 'Upgrade to HD'}
              </button>
            )}
            {p.onManageBilling && (
              <button className="btn btn-ghost" onClick={p.onManageBilling}>
                Manage subscription
              </button>
            )}
            {p.streamMode === 'none' && (
              <button className="btn btn-ghost" onClick={p.onPlayUrl}>
                <IconFilm width={16} height={16} /> Play a video link
              </button>
            )}
            <button className="btn btn-ghost danger" onClick={p.onLeave}>
              Leave room
            </button>
          </div>
        </div>
      )}

      <div className="bar">
        {p.iAmSharing ? (
          <>
            <Btn label="Stop sharing" onClick={p.onStopStream} danger>
              <IconStop />
            </Btn>
            <Btn label="Switch tab / source" onClick={p.onSwitchSource}>
              <IconSwitch />
            </Btn>
          </>
        ) : p.streamMode !== 'none' ? (
          <Btn label={p.streamMode === 'url' ? 'Close video' : 'End their stream'} onClick={p.onStopStream}>
            <IconStop />
          </Btn>
        ) : (
          <Btn label={p.canShare ? 'Share a tab or screen' : 'Sharing needs a desktop browser'} onClick={p.onShare}>
            <IconScreen />
          </Btn>
        )}
        <span className="bar-sep" />
        <Btn label={p.micOn ? 'Mute mic' : 'Unmute mic'} onClick={p.onToggleMic} active={!p.micOn} kbd="M">
          {p.micOn ? <IconMic /> : <IconMicOff />}
        </Btn>
        <Btn label={p.camOn ? 'Turn camera off' : 'Turn camera on'} onClick={p.onToggleCam} active={!p.camOn} kbd="V">
          {p.camOn ? <IconCam /> : <IconCamOff />}
        </Btn>
        <Btn label={p.selfHidden ? 'Show my self-view' : 'Hide my self-view'} onClick={p.onToggleSelf} active={p.selfHidden} kbd="H">
          {p.selfHidden ? <IconEyeOff /> : <IconEye />}
        </Btn>
        <span className="bar-sep" />
        <Btn label="Volume mixer" onClick={() => toggle('mixer')} active={panel === 'mixer'}>
          <IconMixer />
        </Btn>
        <Btn label="Date-night gifts" onClick={() => toggle('gifts')} active={panel === 'gifts'}>
          <IconGift />
        </Btn>
        <Btn label={p.fullscreen ? 'Exit fullscreen' : 'Fullscreen'} onClick={p.onFullscreen} kbd="F">
          {p.fullscreen ? <IconExitFull /> : <IconFull />}
        </Btn>
        <Btn label="Copy invite link" onClick={p.onCopyLink}>
          <IconLink />
        </Btn>
        <Btn label="More" onClick={() => toggle('more')} active={panel === 'more'}>
          {panel === 'more' ? <IconClose /> : <IconMore />}
        </Btn>
      </div>
    </div>
  );
}
