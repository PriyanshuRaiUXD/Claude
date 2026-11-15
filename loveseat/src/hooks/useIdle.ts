import { useEffect, useRef, useState } from 'react';

/**
 * True after `ms` without pointer, touch or key activity. `hold` keeps the UI awake (an open
 * menu, a hovered toolbar) so controls never vanish under the cursor.
 */
export function useIdle(ms: number, hold: boolean): boolean {
  const [idle, setIdle] = useState(false);
  const timer = useRef<number | null>(null);
  const holdRef = useRef(hold);
  holdRef.current = hold;

  useEffect(() => {
    const arm = () => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = window.setTimeout(() => {
        if (!holdRef.current) setIdle(true);
      }, ms);
    };
    const wake = () => {
      setIdle(false);
      arm();
    };
    const leave = (e: MouseEvent) => {
      // Cursor left the window: hide right away, like a real player.
      if (!e.relatedTarget && !holdRef.current) setIdle(true);
    };
    const events = ['pointermove', 'pointerdown', 'keydown', 'wheel', 'touchstart'] as const;
    events.forEach((e) => window.addEventListener(e, wake, { passive: true }));
    document.addEventListener('mouseout', leave);
    arm();
    return () => {
      events.forEach((e) => window.removeEventListener(e, wake));
      document.removeEventListener('mouseout', leave);
      if (timer.current) clearTimeout(timer.current);
    };
  }, [ms]);

  useEffect(() => {
    if (hold) setIdle(false);
    else {
      if (timer.current) clearTimeout(timer.current);
      timer.current = window.setTimeout(() => setIdle(true), ms);
    }
  }, [hold, ms]);

  return idle && !hold;
}
