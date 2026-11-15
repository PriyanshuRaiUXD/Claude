import type { QualityProfile } from '../../shared/catalog';

export const canShareScreen = typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getDisplayMedia;
export const canUseCamera = typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getUserMedia;

export function cameraConstraints(q: QualityProfile): MediaTrackConstraints {
  const { width, height, frameRate } = q.camera;
  return {
    width: { ideal: width },
    height: { ideal: height },
    frameRate: { ideal: frameRate, max: frameRate },
    facingMode: 'user',
  };
}

const MIC_CONSTRAINTS: MediaTrackConstraints = {
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
};

export interface CameraResult {
  audio: MediaStreamTrack | null;
  video: MediaStreamTrack | null;
  /** Human-readable reason when something could not be opened. */
  problem: string | null;
}

function describe(err: unknown, what: string): string {
  const name = (err as DOMException)?.name;
  if (name === 'NotAllowedError' || name === 'SecurityError') return `${what} access was blocked. Allow it from the address bar to be seen and heard.`;
  if (name === 'NotFoundError' || name === 'OverconstrainedError') return `No ${what.toLowerCase()} was found.`;
  if (name === 'NotReadableError') return `Your ${what.toLowerCase()} is busy in another app.`;
  return `${what} could not be started.`;
}

/** Opens mic and/or camera. Partial success is fine: a couple with only a mic can still watch together. */
export async function openCamera(q: QualityProfile, want: { audio: boolean; video: boolean }): Promise<CameraResult> {
  const result: CameraResult = { audio: null, video: null, problem: null };
  if (!canUseCamera) return { ...result, problem: 'This browser cannot use a camera or microphone (it may need https).' };
  if (!want.audio && !want.video) return result;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: want.audio ? MIC_CONSTRAINTS : false,
      video: want.video ? cameraConstraints(q) : false,
    });
    result.audio = stream.getAudioTracks()[0] ?? null;
    result.video = stream.getVideoTracks()[0] ?? null;
  } catch {
    // Try each device separately so one blocked device doesn't take the other down.
    const problems: string[] = [];
    if (want.audio) {
      try {
        result.audio = (await navigator.mediaDevices.getUserMedia({ audio: MIC_CONSTRAINTS })).getAudioTracks()[0] ?? null;
      } catch (err) {
        problems.push(describe(err, 'Microphone'));
      }
    }
    if (want.video) {
      try {
        result.video = (await navigator.mediaDevices.getUserMedia({ video: cameraConstraints(q) })).getVideoTracks()[0] ?? null;
      } catch (err) {
        problems.push(describe(err, 'Camera'));
      }
    }
    result.problem = problems.join(' ') || null;
  }
  if (result.video) result.video.contentHint = 'motion';
  if (result.audio) result.audio.contentHint = 'speech';
  return result;
}

export interface ScreenCapture {
  stream: MediaStream;
  video: MediaStreamTrack;
  audio: MediaStreamTrack | null;
  /** browser | window | monitor */
  surface: string;
  /** True when the browser muted the shared tab locally, so our preview must play its sound. */
  playLocally: boolean;
}

export class ScreenShareCancelled extends Error {}

/**
 * Captures a tab, window or screen with stereo system audio. Processing that helps voices (echo
 * cancellation, noise suppression, AGC) wrecks music and film audio, so it is all turned off here.
 */
export async function openScreen(q: QualityProfile): Promise<ScreenCapture> {
  if (!canShareScreen) throw new Error('Screen sharing needs a desktop browser such as Chrome, Edge, Firefox or Safari.');
  const { width, height, frameRate } = q.screen;
  const options = {
    video: {
      width: { ideal: width, max: width },
      height: { ideal: height, max: height },
      frameRate: { ideal: frameRate, max: frameRate },
    },
    audio: {
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      channelCount: { ideal: 2 },
      sampleRate: { ideal: 48000 },
      // Chrome: mute the shared tab locally; we play the captured sound in sync with the preview instead.
      suppressLocalAudioPlayback: true,
      // Chrome: when sharing a whole screen, don't capture this page's own audio (no echo of your partner).
      restrictOwnAudio: true,
    },
    // Chrome hints: offer system audio, keep our own tab out of the picker, allow "share this tab instead".
    systemAudio: 'include',
    selfBrowserSurface: 'exclude',
    surfaceSwitching: 'include',
    monitorTypeSurfaces: 'include',
  } as DisplayMediaStreamOptions;

  let stream: MediaStream;
  try {
    stream = await navigator.mediaDevices.getDisplayMedia(options);
  } catch (err) {
    const name = (err as DOMException)?.name;
    if (name === 'NotAllowedError' || name === 'AbortError') throw new ScreenShareCancelled('Screen share cancelled');
    throw new Error('Screen sharing could not start.');
  }
  const video = stream.getVideoTracks()[0]!;
  const audio = stream.getAudioTracks()[0] ?? null;
  // Film and sport: keep motion smooth rather than every pixel sharp.
  video.contentHint = 'motion';
  if (audio) audio.contentHint = 'music';
  const settings = video.getSettings() as MediaTrackSettings & { displaySurface?: string };
  const audioSettings = (audio?.getSettings() ?? {}) as MediaTrackSettings & { suppressLocalAudioPlayback?: boolean };
  const surface = settings.displaySurface ?? 'unknown';
  return {
    stream,
    video,
    audio,
    surface,
    playLocally: !!audio && surface === 'browser' && audioSettings.suppressLocalAudioPlayback === true,
  };
}

/** Re-targets an open camera when the room's tier changes (e.g. upgrade mid-call). */
export async function retuneCamera(track: MediaStreamTrack | null, q: QualityProfile): Promise<void> {
  if (!track || track.readyState !== 'live') return;
  try {
    await track.applyConstraints(cameraConstraints(q));
  } catch {
    /* the camera can't do it; keep what we have */
  }
}

export async function retuneScreen(track: MediaStreamTrack | null, q: QualityProfile): Promise<void> {
  if (!track || track.readyState !== 'live') return;
  const { width, height, frameRate } = q.screen;
  try {
    await track.applyConstraints({ width: { ideal: width, max: width }, height: { ideal: height, max: height }, frameRate: { ideal: frameRate, max: frameRate } });
  } catch {
    /* keep current */
  }
}

export function stopTrack(track: MediaStreamTrack | null | undefined): void {
  try {
    track?.stop();
  } catch {
    /* ignore */
  }
}
