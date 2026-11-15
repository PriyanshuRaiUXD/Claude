import { forwardRef, useEffect, useImperativeHandle, useRef } from 'react';
import type { GiftId } from '../../shared/catalog';
import { GiftEngine } from '../lib/gifts';

export interface GiftLayerHandle {
  play: (gift: GiftId, seed: number) => void;
}

export const GiftLayer = forwardRef<GiftLayerHandle>(function GiftLayer(_props, ref) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const engine = useRef<GiftEngine | null>(null);

  useEffect(() => {
    if (!canvas.current) return;
    const e = new GiftEngine(canvas.current);
    engine.current = e;
    const onResize = () => e.resize();
    window.addEventListener('resize', onResize);
    document.addEventListener('fullscreenchange', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      document.removeEventListener('fullscreenchange', onResize);
      e.destroy();
    };
  }, []);

  useImperativeHandle(ref, () => ({ play: (gift, seed) => engine.current?.play(gift, seed) }), []);

  return <canvas ref={canvas} className="gift-layer" aria-hidden />;
});
