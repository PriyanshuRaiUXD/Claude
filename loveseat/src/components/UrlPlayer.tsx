import { useEffect, useRef, useState } from 'react';
import type { UrlPlayback } from '../../shared/types';
import { IconPause, IconPlay } from './Icons';

interface Props {
  playback: UrlPlayback;
  serverNow: () => number;
  volume: number;
  onControl: (playing: boolean, position: number) => void;
  onError: (message: string) => void;
}

function expectedPosition(p: UrlPlayback, now: number): number {
  return p.playing ? p.position + Math.max(0, now - p.updatedAt) / 1000 : p.position;
}

function fmt(seconds: number): string {
  if (!Number.isFinite(seconds)) return '0:00';
  const s = Math.floor(seconds % 60).toString().padStart(2, '0');
  const m = Math.floor(seconds / 60) % 60;
  const h = Math.floor(seconds / 3600);
  return h ? `${h}:${m.toString().padStart(2, '0')}:${s}` : `${m}:${s}`;
}

/**
 * Direct-URL fallback player (MP4, WebM, HLS). The server holds one playback clock; each screen
 * steers toward it: big drift → seek, small drift → nudge playbackRate. Only explicit clicks on
 * our controls are sent, so the two players never echo each other into a loop.
 */
export function UrlPlayer({ playback, serverNow, volume, onControl, onError }: Props) {
  const video = useRef<HTMLVideoElement>(null);
  const [duration, setDuration] = useState(0);
  const [current, setCurrent] = useState(0);
  const [needsTap, setNeedsTap] = useState(false);
  const [buffering, setBuffering] = useState(false);
  /** Position under the thumb while scrubbing; sent once on release, not on every pixel. */
  const [scrub, setScrub] = useState<number | null>(null);
  const latest = useRef(playback);
  latest.current = playback;

  // Load source (hls.js only when the browser can't play HLS natively).
  useEffect(() => {
    const v = video.current;
    if (!v) return;
    let destroy: (() => void) | undefined;
    const isHls = /\.m3u8($|\?)/i.test(playback.src);
    if (isHls && !v.canPlayType('application/vnd.apple.mpegurl')) {
      let cancelled = false;
      void import('hls.js').then(({ default: Hls }) => {
        if (cancelled) return;
        if (!Hls.isSupported()) return onError('This browser cannot play HLS streams.');
        const hls = new Hls({ enableWorker: true });
        hls.on(Hls.Events.ERROR, (_e, data) => {
          if (data.fatal) onError('The stream could not be loaded (it may block other websites with CORS).');
        });
        hls.loadSource(playback.src);
        hls.attachMedia(v);
        destroy = () => hls.destroy();
      });
      return () => {
        cancelled = true;
        destroy?.();
      };
    }
    v.src = playback.src;
    return () => {
      v.removeAttribute('src');
      v.load();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playback.src]);

  useEffect(() => {
    if (video.current) video.current.volume = volume;
  }, [volume]);

  // Steering loop.
  useEffect(() => {
    const tick = () => {
      const v = video.current;
      if (!v || v.readyState < 1) return;
      const p = latest.current;
      const target = expectedPosition(p, serverNow());
      const drift = target - v.currentTime;
      if (Math.abs(drift) > 1.0) {
        v.currentTime = target;
        v.playbackRate = 1;
      } else if (p.playing && Math.abs(drift) > 0.12) {
        v.playbackRate = 1 + Math.max(-0.08, Math.min(0.08, drift * 0.4));
      } else {
        v.playbackRate = 1;
      }
      if (p.playing && v.paused) {
        v.play().then(
          () => setNeedsTap(false),
          (err: DOMException) => err?.name === 'NotAllowedError' && setNeedsTap(true),
        );
      } else if (!p.playing && !v.paused) {
        v.pause();
      }
      setCurrent(v.currentTime);
    };
    tick();
    const t = window.setInterval(tick, 400);
    return () => clearInterval(t);
  }, [serverNow]);

  const toggle = () => {
    const v = video.current;
    const pos = v ? v.currentTime : expectedPosition(playback, serverNow());
    onControl(!playback.playing, pos);
  };

  const commit = () => {
    if (scrub === null) return;
    onControl(playback.playing, scrub);
    setScrub(null);
  };

  return (
    <div className="urlplayer">
      <video
        ref={video}
        playsInline
        preload="auto"
        onLoadedMetadata={(e) => setDuration(e.currentTarget.duration)}
        onWaiting={() => setBuffering(true)}
        onPlaying={() => setBuffering(false)}
        onCanPlay={() => setBuffering(false)}
        onError={() => onError('This video link could not be played. It must be a direct link to an .mp4, .webm or .m3u8 file.')}
        onClick={toggle}
      />
      {buffering && <div className="urlplayer-buffer">Buffering…</div>}
      {needsTap && (
        <button className="tap-to-play" onClick={() => video.current?.play().then(() => setNeedsTap(false), () => {})}>
          Tap to join playback
        </button>
      )}
      <div className="urlplayer-bar hover-ui">
        <button className="icon-btn" onClick={toggle} aria-label={playback.playing ? 'Pause for both' : 'Play for both'}>
          {playback.playing ? <IconPause /> : <IconPlay />}
        </button>
        <span className="urlplayer-time">{fmt(current)}</span>
        <input
          type="range"
          min={0}
          max={duration || 0}
          step={0.5}
          value={Math.min(scrub ?? current, duration || 0)}
          onChange={(e) => setScrub(Number(e.target.value))}
          onPointerUp={commit}
          onKeyUp={commit}
          onBlur={commit}
          aria-label="Seek for both"
        />
        <span className="urlplayer-time">{fmt(duration)}</span>
      </div>
    </div>
  );
}
