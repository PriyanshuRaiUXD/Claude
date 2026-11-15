import { useCallback, useEffect, useRef, useState, type PointerEvent as RPointerEvent, type ReactNode } from 'react';
import type { FrameId } from '../../shared/catalog';
import { prefs, type BubbleRect } from '../lib/storage';
import { VideoEl } from './VideoEl';

interface Props {
  id: 'self' | 'partner';
  stream: MediaStream | null;
  name: string;
  camOn: boolean;
  micOn: boolean;
  muted?: boolean;
  volume?: number;
  mirrored?: boolean;
  frame: FrameId;
  defaultRect: BubbleRect;
  /** Extra hover-only action, e.g. "hide me". */
  action?: ReactNode;
  status?: string;
}

const MIN_W = 120;
const MAX_W_FRACTION = 0.6;
const ASPECT = 4 / 3;

function clampRect(r: BubbleRect, vw: number, vh: number): BubbleRect {
  const wPx = Math.min(Math.max(r.w * vw, MIN_W), vw * MAX_W_FRACTION);
  const hPx = wPx / ASPECT;
  const w = wPx / vw;
  const x = Math.min(Math.max(r.x, 0), Math.max(0, 1 - w));
  const y = Math.min(Math.max(r.y, 0), Math.max(0, 1 - hPx / vh));
  return { x, y, w };
}

/**
 * Floating picture-in-picture webcam. Drag anywhere to move, drag the corner to resize.
 * Geometry is stored as viewport fractions so it stays put across resizes and reloads.
 */
export function CamBubble({ id, stream, name, camOn, micOn, muted, volume, mirrored, frame, defaultRect, action, status }: Props) {
  const [rect, setRect] = useState<BubbleRect>(() => prefs.bubbles()[id] ?? defaultRect);
  const [vp, setVp] = useState({ w: window.innerWidth, h: window.innerHeight });
  const drag = useRef<{ mode: 'move' | 'resize'; startX: number; startY: number; start: BubbleRect } | null>(null);
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    const onResize = () => setVp({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  const r = clampRect(rect, vp.w, vp.h);

  const persist = useCallback(
    (next: BubbleRect) => {
      prefs.setBubbles({ ...prefs.bubbles(), [id]: next });
    },
    [id],
  );

  const onPointerDown = (mode: 'move' | 'resize') => (e: RPointerEvent) => {
    if (e.button !== 0) return;
    // Buttons inside the bubble must stay clickable; pointer capture would steal their click.
    if ((e.target as HTMLElement).closest('button')) return;
    e.stopPropagation();
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
    drag.current = { mode, startX: e.clientX, startY: e.clientY, start: r };
    setDragging(true);
  };

  const onPointerMove = (e: RPointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const dx = (e.clientX - d.startX) / vp.w;
    const dy = (e.clientY - d.startY) / vp.h;
    if (d.mode === 'move') setRect(clampRect({ ...d.start, x: d.start.x + dx, y: d.start.y + dy }, vp.w, vp.h));
    else setRect(clampRect({ ...d.start, w: d.start.w + dx }, vp.w, vp.h));
  };

  const onPointerUp = () => {
    if (!drag.current) return;
    drag.current = null;
    setDragging(false);
    persist(clampRect(rect, vp.w, vp.h));
  };

  const hasVideo = camOn && !!stream && stream.getVideoTracks().some((t) => t.readyState === 'live');

  return (
    <div
      className={`bubble frame-${frame} ${dragging ? 'is-dragging' : ''}`}
      style={{ left: `${r.x * 100}%`, top: `${r.y * 100}%`, width: `${r.w * 100}%` }}
      onPointerDown={onPointerDown('move')}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onDoubleClick={() => {
        setRect(defaultRect);
        persist(defaultRect);
      }}
      title="Drag to move · drag corner to resize · double-click to reset"
    >
      <div className="bubble-inner">
        {/* Audio keeps playing from this element even while the partner's camera is off. */}
        <VideoEl stream={stream} muted={muted} volume={volume} mirrored={mirrored} className={hasVideo ? '' : 'is-hidden'} />
        {!hasVideo && (
          <div className="bubble-avatar">
            <span>{name.slice(0, 1).toUpperCase()}</span>
          </div>
        )}
        <div className="bubble-label">
          {!micOn && <span className="bubble-muted" aria-label="muted">●</span>}
          {name}
          {status && <em>{status}</em>}
        </div>
        {action && <div className="bubble-action">{action}</div>}
      </div>
      <div className="bubble-resize" onPointerDown={onPointerDown('resize')} aria-hidden />
    </div>
  );
}
