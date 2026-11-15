import type { SVGProps } from 'react';

type P = SVGProps<SVGSVGElement>;
const base = { width: 22, height: 22, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' } as const;

export const IconScreen = (p: P) => (
  <svg {...base} {...p}><rect x="3" y="4" width="18" height="12" rx="2" /><path d="M8 20h8M12 16v4" /></svg>
);
export const IconStop = (p: P) => (
  <svg {...base} {...p}><rect x="3" y="4" width="18" height="12" rx="2" /><path d="m9 7 6 6M15 7l-6 6" /></svg>
);
export const IconSwitch = (p: P) => (
  <svg {...base} {...p}><path d="M4 7h13l-3-3M20 17H7l3 3" /></svg>
);
export const IconMic = (p: P) => (
  <svg {...base} {...p}><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" /></svg>
);
export const IconMicOff = (p: P) => (
  <svg {...base} {...p}><path d="M15 9.5V6a3 3 0 0 0-5.8-1M9 9v2a3 3 0 0 0 4.6 2.5M5 11a7 7 0 0 0 11.4 5.4M19 11a7 7 0 0 1-.6 2.8M12 18v3M3 3l18 18" /></svg>
);
export const IconCam = (p: P) => (
  <svg {...base} {...p}><rect x="3" y="6" width="13" height="12" rx="2" /><path d="m16 10 5-3v10l-5-3" /></svg>
);
export const IconCamOff = (p: P) => (
  <svg {...base} {...p}><path d="M16 16v1a1 1 0 0 1-1 1H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h1M10 6h5a1 1 0 0 1 1 1v3l5-3v10M3 3l18 18" /></svg>
);
export const IconEye = (p: P) => (
  <svg {...base} {...p}><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" /><circle cx="12" cy="12" r="3" /></svg>
);
export const IconEyeOff = (p: P) => (
  <svg {...base} {...p}><path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.4 0 10 7 10 7a17.6 17.6 0 0 1-3 3.9M6.6 6.6C3.8 8.4 2 12 2 12s3.6 7 10 7c1.9 0 3.5-.6 4.9-1.5M9.9 9.9a3 3 0 0 0 4.2 4.2M3 3l18 18" /></svg>
);
export const IconMixer = (p: P) => (
  <svg {...base} {...p}><path d="M6 4v6M6 14v6M12 4v2M12 10v10M18 4v10M18 18v2" /><circle cx="6" cy="12" r="2" /><circle cx="12" cy="8" r="2" /><circle cx="18" cy="16" r="2" /></svg>
);
export const IconGift = (p: P) => (
  <svg {...base} {...p}><rect x="3" y="8" width="18" height="4" rx="1" /><path d="M12 8v13M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7M7.5 8a2.5 2.5 0 0 1 0-5C10 3 12 8 12 8s2-5 4.5-5a2.5 2.5 0 0 1 0 5" /></svg>
);
export const IconFull = (p: P) => (
  <svg {...base} {...p}><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" /></svg>
);
export const IconExitFull = (p: P) => (
  <svg {...base} {...p}><path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5" /></svg>
);
export const IconLink = (p: P) => (
  <svg {...base} {...p}><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" /></svg>
);
export const IconPlay = (p: P) => (
  <svg {...base} {...p}><path d="M7 4.5v15l12-7.5-12-7.5Z" fill="currentColor" stroke="none" /></svg>
);
export const IconPause = (p: P) => (
  <svg {...base} {...p}><path d="M8 5v14M16 5v14" strokeWidth={3} /></svg>
);
export const IconFilm = (p: P) => (
  <svg {...base} {...p}><rect x="3" y="3" width="18" height="18" rx="2" /><path d="M7 3v18M17 3v18M3 8h4M3 16h4M17 8h4M17 16h4" /></svg>
);
export const IconSparkle = (p: P) => (
  <svg {...base} {...p}><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3ZM19 16l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7.7-2Z" /></svg>
);
export const IconMore = (p: P) => (
  <svg {...base} {...p}><circle cx="5" cy="12" r="1.4" fill="currentColor" /><circle cx="12" cy="12" r="1.4" fill="currentColor" /><circle cx="19" cy="12" r="1.4" fill="currentColor" /></svg>
);
export const IconClose = (p: P) => (
  <svg {...base} {...p}><path d="M6 6l12 12M18 6 6 18" /></svg>
);
export const IconHeart = (p: P) => (
  <svg {...base} {...p}><path d="M12 20s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7.6 4.3 4.3 0 0 1 19.5 10c0 5.6-7.5 10-7.5 10Z" fill="currentColor" stroke="none" /></svg>
);
export const IconLock = (p: P) => (
  <svg {...base} {...p}><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></svg>
);
