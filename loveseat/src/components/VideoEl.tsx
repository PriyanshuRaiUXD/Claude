import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from 'react';

interface Props {
  stream: MediaStream | null;
  muted?: boolean;
  volume?: number;
  mirrored?: boolean;
  fit?: 'cover' | 'contain';
  className?: string;
  onPlaying?: () => void;
}

/** A <video> bound to a MediaStream, with an autoplay-blocked fallback. */
export const VideoEl = forwardRef<HTMLVideoElement | null, Props>(function VideoEl(
  { stream, muted = false, volume = 1, mirrored = false, fit = 'cover', className, onPlaying },
  ref,
) {
  const el = useRef<HTMLVideoElement | null>(null);
  const [blocked, setBlocked] = useState(false);
  useImperativeHandle(ref, () => el.current as HTMLVideoElement);

  useEffect(() => {
    const v = el.current;
    if (!v) return;
    if (v.srcObject !== stream) v.srcObject = stream;
    if (!stream) return;
    v.play().then(
      () => setBlocked(false),
      (err: DOMException) => {
        if (err?.name === 'NotAllowedError') setBlocked(true);
      },
    );
  }, [stream]);

  useEffect(() => {
    if (el.current) el.current.volume = Math.max(0, Math.min(1, volume));
  }, [volume]);

  return (
    <>
      <video
        ref={el}
        className={className}
        autoPlay
        playsInline
        muted={muted}
        onPlaying={onPlaying}
        style={{ objectFit: fit, transform: mirrored ? 'scaleX(-1)' : undefined }}
      />
      {blocked && (
        <button
          className="tap-to-play"
          onClick={() => {
            el.current?.play().then(() => setBlocked(false), () => {});
          }}
        >
          Tap to turn on sound
        </button>
      )}
    </>
  );
});
