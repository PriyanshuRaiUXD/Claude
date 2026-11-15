import { useEffect, useState } from 'react';

/** Tiny history router: the app has four routes and doesn't need a library for them. */
export function navigate(to: string, replace = false): void {
  if (replace) window.history.replaceState(null, '', to);
  else window.history.pushState(null, '', to);
  window.dispatchEvent(new PopStateEvent('popstate'));
}

export function useLocation(): { path: string; search: URLSearchParams } {
  const [loc, setLoc] = useState(() => ({ path: window.location.pathname, search: new URLSearchParams(window.location.search) }));
  useEffect(() => {
    const on = () => setLoc({ path: window.location.pathname, search: new URLSearchParams(window.location.search) });
    window.addEventListener('popstate', on);
    return () => window.removeEventListener('popstate', on);
  }, []);
  return loc;
}
