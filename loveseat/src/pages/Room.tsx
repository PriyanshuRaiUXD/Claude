import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { GIFTS, QUALITY, type FrameId, type GiftId, type QualityProfile, type Tier } from '../../shared/catalog';
import type { GiftPlay, IceServer, Participant, PublicConfig, RoomState, SignalPayload } from '../../shared/types';
import { CamBubble } from '../components/CamBubble';
import { Controls } from '../components/Controls';
import { GiftLayer, type GiftLayerHandle } from '../components/GiftLayer';
import { IconCam, IconCamOff, IconEyeOff, IconMic, IconMicOff } from '../components/Icons';
import { Lobby } from '../components/Lobby';
import { Toasts, useToasts } from '../components/Toasts';
import { UpgradeSheet, type UpgradeReason } from '../components/UpgradeSheet';
import { UrlPlayer } from '../components/UrlPlayer';
import { VideoEl } from '../components/VideoEl';
import { useIdle } from '../hooks/useIdle';
import { api, loadConfig } from '../lib/api';
import { canShareScreen, openCamera, openScreen, retuneCamera, retuneScreen, ScreenShareCancelled, stopTrack, type ScreenCapture } from '../lib/media';
import { PeerLink, type LinkStats, type RemoteMedia } from '../lib/peer';
import { ServerClock, connectSocket, type RoomSocket } from '../lib/socket';
import { clientId, hasSeat, prefs } from '../lib/storage';
import { navigate } from '../router';

type Phase = 'checking' | 'missing' | 'full' | 'prejoin' | 'joining' | 'in' | 'replaced' | 'error';

const CHANNEL = 'loveseat-checkout';

function clockText(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const m = Math.floor(total / 60);
  const s = (total % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}

export function Room({ roomId }: { roomId: string }) {
  const [phase, setPhase] = useState<Phase>('checking');
  const [config, setConfig] = useState<PublicConfig | null>(null);
  const [initialTier, setInitialTier] = useState<Tier>('free');
  const [name, setName] = useState(prefs.name());

  // ---- local media (one MediaStream whose tracks we swap; its id is what the partner knows us by)
  const camStream = useMemo(() => new MediaStream(), []);
  const [audioTrack, setAudioTrack] = useState<MediaStreamTrack | null>(null);
  const [videoTrack, setVideoTrack] = useState<MediaStreamTrack | null>(null);
  const [micOn, setMicOn] = useState(prefs.media().micOn);
  const [camOn, setCamOn] = useState(prefs.media().camOn);
  const [mediaProblem, setMediaProblem] = useState<string | null>(null);
  const selfPreview = useMemo(() => (videoTrack ? new MediaStream([videoTrack]) : null), [videoTrack]);

  // ---- room
  const [state, setState] = useState<RoomState | null>(null);
  const [selfId, setSelfId] = useState('');
  const [remote, setRemote] = useState<RemoteMedia>({ cam: null, screen: null });
  const [peerState, setPeerState] = useState<RTCPeerConnectionState | 'none'>('none');
  const [stats, setStats] = useState<LinkStats | null>(null);
  const [capture, setCapture] = useState<ScreenCapture | null>(null);

  // ---- ui
  const [selfHidden, setSelfHidden] = useState(prefs.selfHidden());
  const [mixer, setMixerState] = useState(prefs.mixer());
  const [fullscreen, setFullscreen] = useState(false);
  const [upgrade, setUpgrade] = useState<UpgradeReason | null>(null);
  const [urlPrompt, setUrlPrompt] = useState(false);
  const [hold, setHold] = useState(false);
  const [now, setNow] = useState(Date.now());
  const [manageVersion, setManageVersion] = useState(0);
  const idle = useIdle(3000, hold || urlPrompt || upgrade !== null);
  const { toasts, push: toast, dismiss } = useToasts();

  // ---- refs for socket callbacks (avoid stale closures)
  const socketRef = useRef<RoomSocket | null>(null);
  const peerRef = useRef<PeerLink | null>(null);
  const iceRef = useRef<IceServer[]>([]);
  const clock = useRef(new ServerClock());
  const giftLayer = useRef<GiftLayerHandle>(null);
  const live = useRef({ selfId: '', state: null as RoomState | null, audio: null as MediaStreamTrack | null, video: null as MediaStreamTrack | null, micOn, camOn, name, capture: null as ScreenCapture | null });
  live.current = { selfId, state, audio: audioTrack, video: videoTrack, micOn, camOn, name, capture };

  const quality: QualityProfile = QUALITY[state?.entitlement.quality ?? (initialTier === 'free' ? 'sd' : 'hd')];
  const qualityRef = useRef(quality);
  qualityRef.current = quality;

  const partner: Participant | null = state?.participants.find((p) => p.id !== selfId) ?? null;
  const serverNow = useCallback(() => clock.current.now(), []);

  // ------------------------------------------------------------ bootstrap --

  useEffect(() => {
    let cancelled = false;
    Promise.all([loadConfig(), api.room(roomId)])
      .then(([cfg, room]) => {
        if (cancelled) return;
        setConfig(cfg);
        setInitialTier(room.tier);
        setPhase(room.full && !hasSeat(roomId) ? 'full' : 'prejoin');
      })
      .catch((err: { status?: number }) => !cancelled && setPhase(err?.status === 404 ? 'missing' : 'error'));
    return () => {
      cancelled = true;
    };
  }, [roomId]);

  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  // Open camera + mic once, for the pre-join preview. It must survive the person clicking Join while
  // the permission prompt is still up, so it is tied to the page's lifetime, not to the phase.
  const cameraRequested = useRef(false);
  useEffect(() => {
    if (phase !== 'prejoin' || cameraRequested.current) return;
    cameraRequested.current = true;
    const want = prefs.media();
    void openCamera(QUALITY[initialTier === 'free' ? 'sd' : 'hd'], { audio: true, video: want.camOn }).then((res) => {
      if (!mounted.current) {
        stopTrack(res.audio);
        stopTrack(res.video);
        return;
      }
      if (res.audio) res.audio.enabled = want.micOn;
      const m = !!res.audio && want.micOn;
      const c = !!res.video;
      setLocalTracks(res.audio, res.video);
      setMicOn(m);
      setCamOn(c);
      setMediaProblem(res.problem);
      // Already in the room by the time the devices opened: tell the partner.
      socketRef.current?.emit('media:state', { micOn: m, camOn: c });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase]);

  const setLocalTracks = useCallback(
    (audio: MediaStreamTrack | null, video: MediaStreamTrack | null) => {
      for (const t of camStream.getTracks()) if (t !== audio && t !== video) camStream.removeTrack(t);
      if (audio && !camStream.getTracks().includes(audio)) camStream.addTrack(audio);
      if (video && !camStream.getTracks().includes(video)) camStream.addTrack(video);
      setAudioTrack(audio);
      setVideoTrack(video);
      void peerRef.current?.setCamTracks(audio, video);
    },
    [camStream],
  );

  // --------------------------------------------------------------- peer --

  const destroyPeer = useCallback(() => {
    peerRef.current?.close();
    peerRef.current = null;
    setRemote({ cam: null, screen: null });
    setPeerState('none');
    setStats(null);
  }, []);

  const createPeer = useCallback(
    (partnerId: string) => {
      destroyPeer();
      const socket = socketRef.current;
      if (!socket) return;
      const link = new PeerLink({
        iceServers: iceRef.current,
        polite: live.current.selfId > partnerId,
        send: (payload: SignalPayload) => socket.emit('signal', payload),
        camStream,
        profile: qualityRef.current,
        onRemote: setRemote,
        onConnection: setPeerState,
        onStats: setStats,
      });
      peerRef.current = link;
      void link.setCamTracks(live.current.audio, live.current.video);
      // Rebuilt mid-share (partner reloaded): put the screen back on the new connection.
      const cap = live.current.capture;
      if (cap && cap.video.readyState === 'live') void link.setScreen(cap);
    },
    [camStream, destroyPeer],
  );

  // ------------------------------------------------------------- socket --

  const join = useCallback(() => {
    const trimmed = name.trim().slice(0, 24) || 'Partner';
    prefs.setName(trimmed);
    setName(trimmed);
    setPhase('joining');
    const socket = connectSocket();
    socketRef.current = socket;

    const doJoin = () => {
      const l = live.current;
      socket.emit(
        'room:join',
        { roomId, clientId: clientId(roomId), name: trimmed, micOn: l.micOn, camOn: l.camOn, sharing: !!l.capture && l.capture.video.readyState === 'live' },
        (res) => {
          if (!res.ok) {
            socket.disconnect();
            setPhase(res.error === 'not_found' ? 'missing' : res.error === 'full' ? 'full' : 'error');
            return;
          }
          clock.current.seed(res.serverNow);
          void clock.current.refine(socket);
          iceRef.current = res.iceServers;
          live.current.selfId = res.selfId;
          setSelfId(res.selfId);
          setState(res.state);
          setPhase('in');
          const other = res.state.participants.find((p) => p.id !== res.selfId && p.connected);
          if (other) createPeer(other.id);
          else destroyPeer();
        },
      );
    };

    socket.on('connect', doJoin); // also fires after every automatic reconnect
    socket.on('room:state', (s) => setState(s));
    socket.on('peer:joined', ({ id }) => {
      createPeer(id);
    });
    socket.on('peer:left', () => {
      destroyPeer();
      toast('Your partner left the room. The link still works if they come back.');
    });
    socket.on('signal', (payload) => peerRef.current?.handleSignal(payload));
    socket.on('gift:play', (play: GiftPlay) => {
      giftLayer.current?.play(play.giftId, play.seed);
      if (play.from !== live.current.selfId) {
        const g = GIFTS.find((x) => x.id === play.giftId);
        if (g) toast(`${play.fromName} sent ${g.name.toLowerCase()} ${g.emoji}`, { tone: 'love' });
      }
    });
    socket.on('session:warning', ({ msLeft }) => {
      toast(`${Math.ceil(msLeft / 60_000)} minutes left in your free hour.`, {
        tone: 'warn',
        ms: 9000,
        action: { label: 'Keep watching', run: () => setUpgrade('warning') },
      });
    });
    socket.on('session:expired', () => setUpgrade('expired'));
    socket.on('entitlement:upgraded', ({ tier }) => {
      setUpgrade(null);
      toast(tier === 'pro' ? 'Couples Pro is on — 1080p60, no limits, for both of you ♥' : 'Date Night Pass is on — 1080p60 for the next 24 hours ♥', { tone: 'love', ms: 6000 });
    });
    socket.on('sparks:added', ({ amount }) => toast(`+${amount} gift Sparks added to your room ✦`, { tone: 'love' }));
    socket.on('session:replaced', () => {
      socket.io.opts.reconnection = false;
      destroyPeer();
      setPhase('replaced');
    });
    socket.on('connect_error', () => {
      if (live.current.state === null) setPhase('error');
    });
  }, [name, roomId, createPeer, destroyPeer, toast]);

  // Full teardown when leaving the page.
  useEffect(
    () => () => {
      peerRef.current?.close();
      socketRef.current?.disconnect();
      const l = live.current;
      stopTrack(l.audio);
      stopTrack(l.video);
      l.capture?.stream.getTracks().forEach(stopTrack);
    },
    [],
  );

  // -------------------------------------------------- quality gating --

  // Tier changed (upgrade, pass ran out): retarget camera, screen and encoder ceilings live.
  useEffect(() => {
    if (phase !== 'in') return;
    void retuneCamera(videoTrack, quality);
    void retuneScreen(capture?.video ?? null, quality);
    void peerRef.current?.setProfile(quality);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [quality.id, phase]);

  // ------------------------------------------------------ screen share --

  const endLocalCapture = useCallback(() => {
    const cap = live.current.capture;
    if (!cap) return;
    cap.stream.getTracks().forEach(stopTrack);
    live.current.capture = null;
    setCapture(null);
    void peerRef.current?.setScreen(null);
  }, []);

  // The server ended our share (session expired, partner pressed stop, or a URL took over).
  useEffect(() => {
    if (!capture || !state) return;
    if (state.stream.mode !== 'screen' || state.stream.by !== selfId) endLocalCapture();
  }, [state, capture, selfId, endLocalCapture]);

  const stopShare = useCallback(() => {
    endLocalCapture();
    socketRef.current?.emit('stream:stop');
  }, [endLocalCapture]);

  const startShare = useCallback(async () => {
    const s = live.current.state;
    if (!canShareScreen) return toast('Screen sharing needs a desktop browser such as Chrome or Edge.', { tone: 'warn' });
    if (s?.session.state === 'cooldown') return setUpgrade('expired');
    if (s && s.stream.mode === 'screen' && s.stream.by !== live.current.selfId) {
      return toast(`${partner?.name ?? 'Your partner'} is sharing right now. End their stream first.`, { tone: 'warn' });
    }
    let cap: ScreenCapture;
    try {
      cap = await openScreen(qualityRef.current);
    } catch (err) {
      if (!(err instanceof ScreenShareCancelled)) toast((err as Error).message, { tone: 'warn' });
      return;
    }
    socketRef.current?.emit('stream:start', { mode: 'screen' }, (res) => {
      if (!res.ok) {
        cap.stream.getTracks().forEach(stopTrack);
        if (res.error === 'session_locked') setUpgrade('expired');
        else if (res.error === 'busy') toast('Your partner started sharing first.', { tone: 'warn' });
        else toast('Could not start the stream.', { tone: 'warn' });
        return;
      }
      live.current.capture = cap;
      setCapture(cap);
      void peerRef.current?.setScreen(cap);
      // The browser's own "Stop sharing" button.
      cap.video.addEventListener('ended', () => {
        if (live.current.capture === cap) stopShare();
      });
      if (!cap.audio) toast('No sound is being shared. To include it, share a browser tab and tick “Share tab audio”.', { tone: 'warn', ms: 8000 });
    });
  }, [partner?.name, stopShare, toast]);

  const switchSource = useCallback(async () => {
    const old = live.current.capture;
    if (!old) return startShare();
    let cap: ScreenCapture;
    try {
      cap = await openScreen(qualityRef.current);
    } catch (err) {
      if (!(err instanceof ScreenShareCancelled)) toast((err as Error).message, { tone: 'warn' });
      return;
    }
    live.current.capture = cap;
    setCapture(cap);
    await peerRef.current?.setScreen(cap); // swaps tracks in place: no gap for the partner
    old.stream.getTracks().forEach(stopTrack);
    cap.video.addEventListener('ended', () => {
      if (live.current.capture === cap) stopShare();
    });
  }, [startShare, stopShare, toast]);

  // --------------------------------------------------------- URL video --

  const playUrl = useCallback(
    (src: string) => {
      if (live.current.state?.session.state === 'cooldown') return setUpgrade('expired');
      socketRef.current?.emit('stream:start', { mode: 'url', src }, (res) => {
        if (res.ok) return setUrlPrompt(false);
        if (res.error === 'session_locked') {
          setUrlPrompt(false);
          setUpgrade('expired');
        } else if (res.error === 'invalid_url') toast('That doesn’t look like a web link.', { tone: 'warn' });
        else if (res.error === 'busy') toast('Your partner is sharing right now.', { tone: 'warn' });
      });
    },
    [toast],
  );

  // ------------------------------------------------------------ devices --

  const emitMedia = (m: boolean, c: boolean) => {
    prefs.setMedia({ micOn: m, camOn: c });
    socketRef.current?.emit('media:state', { micOn: m, camOn: c });
  };

  const toggleMic = useCallback(async () => {
    const l = live.current;
    if (l.audio && l.audio.readyState === 'live') {
      l.audio.enabled = !l.micOn;
      setMicOn(!l.micOn);
      emitMedia(!l.micOn, l.camOn);
      return;
    }
    const res = await openCamera(qualityRef.current, { audio: true, video: false });
    if (!res.audio) return toast(res.problem ?? 'Microphone unavailable', { tone: 'warn' });
    setLocalTracks(res.audio, live.current.video);
    setMicOn(true);
    emitMedia(true, live.current.camOn);
  }, [setLocalTracks, toast]);

  const toggleCam = useCallback(async () => {
    const l = live.current;
    if (l.camOn && l.video) {
      // Really release the camera (the light goes off), not just send black frames.
      stopTrack(l.video);
      setLocalTracks(l.audio, null);
      setCamOn(false);
      emitMedia(l.micOn, false);
      return;
    }
    const res = await openCamera(qualityRef.current, { audio: false, video: true });
    if (!res.video) return toast(res.problem ?? 'Camera unavailable', { tone: 'warn' });
    setLocalTracks(live.current.audio, res.video);
    setCamOn(true);
    emitMedia(live.current.micOn, true);
  }, [setLocalTracks, toast]);

  const toggleSelf = useCallback(() => {
    setSelfHidden((h) => {
      prefs.setSelfHidden(!h);
      if (!h) toast('Self-view hidden. Your partner can still see you.', { action: { label: 'Show me', run: () => setSelfHidden(false) } });
      return !h;
    });
  }, [toast]);

  useEffect(() => prefs.setSelfHidden(selfHidden), [selfHidden]);

  const setMixer = (v: { stream: number; voice: number }) => {
    setMixerState(v);
    prefs.setMixer(v);
  };

  // --------------------------------------------------------- room actions --

  const copyLink = useCallback(async () => {
    const link = `${window.location.origin}/r/${roomId}`;
    try {
      await navigator.clipboard.writeText(link);
      toast('Invite link copied. Send it to your person ♥', { tone: 'love' });
    } catch {
      window.prompt('Copy this link and send it to your partner:', link);
    }
  }, [roomId, toast]);

  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void document.documentElement.requestFullscreen?.().catch(() => toast('Fullscreen is not available here.'));
  }, [toast]);

  useEffect(() => {
    const onFs = () => setFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onFs);
    return () => document.removeEventListener('fullscreenchange', onFs);
  }, []);

  const sendGift = useCallback(
    (giftId: GiftId) => {
      socketRef.current?.emit('gift:send', { giftId }, (res) => {
        if (res.ok) return;
        if (res.error === 'insufficient') setUpgrade('sparks');
        else if (res.error === 'cooldown') toast('One at a time — let that one land ♥');
      });
    },
    [toast],
  );

  const setFrame = useCallback(
    (frame: FrameId) => {
      socketRef.current?.emit('frame:set', { frame }, (res) => {
        if (!res.ok && res.error === 'pro_required') setUpgrade('frames');
      });
    },
    [],
  );

  const manageToken = useMemo(() => prefs.manageToken(roomId), [roomId, manageVersion]);
  const manageBilling = useCallback(async () => {
    if (!manageToken) return;
    try {
      const { url } = await api.portal(roomId, manageToken);
      window.open(url, '_blank', 'noopener');
    } catch (err) {
      toast((err as Error).message, { tone: 'warn' });
    }
  }, [manageToken, roomId, toast]);

  const leave = useCallback(() => {
    socketRef.current?.disconnect();
    navigate('/');
  }, []);

  const onLobbyAction = useCallback((action: string) => {
    if (action === 'pass' || action === 'pro') setUpgrade('manual');
    else if (action === 'gifts') setUpgrade('sparks');
  }, []);

  // Checkout tabs report back here (and the room socket confirms the entitlement for both partners).
  useEffect(() => {
    if (typeof BroadcastChannel === 'undefined') return;
    const ch = new BroadcastChannel(CHANNEL);
    ch.onmessage = (e: MessageEvent<{ roomId: string; status: string }>) => {
      if (e.data?.roomId !== roomId) return;
      setManageVersion((v) => v + 1);
      if (e.data.status === 'cancelled') toast('Checkout closed — nothing was charged.');
    };
    return () => ch.close();
  }, [roomId, toast]);

  // Keyboard shortcuts.
  useEffect(() => {
    if (phase !== 'in') return;
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t.closest('input, textarea, [contenteditable]') || e.metaKey || e.ctrlKey || e.altKey) return;
      const k = e.key.toLowerCase();
      if (k === 'm') void toggleMic();
      else if (k === 'v') void toggleCam();
      else if (k === 'h') toggleSelf();
      else if (k === 'f') toggleFullscreen();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [phase, toggleMic, toggleCam, toggleSelf, toggleFullscreen]);

  // One-second tick for the session clock.
  useEffect(() => {
    if (state?.session.state === 'idle' || !state) return;
    const t = window.setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [state?.session.state, state]);

  // ---------------------------------------------------------------- views --

  if (phase === 'checking') return <div className="center-screen"><div className="spinner" aria-label="Loading" /></div>;

  if (phase === 'missing' || phase === 'full' || phase === 'replaced' || phase === 'error') {
    const copy = {
      missing: { h: 'This room doesn’t exist', p: 'The link may be mistyped, or the room expired after 30 days without use.' },
      full: { h: 'This room already has two people', p: 'Loveseat rooms are for exactly two. Ask your partner for a fresh link if this seems wrong.' },
      replaced: { h: 'You opened this room in another tab', p: 'Only one tab per person can be in the room. Close the other tab or continue here.' },
      error: { h: 'Can’t reach the room right now', p: 'Check your connection and try again.' },
    }[phase];
    return (
      <div className="center-screen">
        <div className="card narrow">
          <h1>{copy.h}</h1>
          <p className="muted">{copy.p}</p>
          <div className="row">
            {phase === 'replaced' || phase === 'error' ? (
              <button className="btn btn-primary" onClick={() => window.location.reload()}>
                {phase === 'replaced' ? 'Use this tab' : 'Try again'}
              </button>
            ) : (
              <button className="btn btn-primary" onClick={() => navigate('/')}>
                Open a new room
              </button>
            )}
          </div>
        </div>
      </div>
    );
  }

  if (phase === 'prejoin' || phase === 'joining') {
    return (
      <div className="center-screen prejoin">
        <div className="prejoin-preview">
          {selfPreview && camOn ? <VideoEl stream={selfPreview} muted mirrored /> : <div className="prejoin-nocam">{camOn ? 'Starting camera…' : 'Camera is off'}</div>}
          <div className="prejoin-devices">
            <button className={`ctl ${micOn ? '' : 'is-active'}`} onClick={() => void toggleMic()} aria-label={micOn ? 'Mute mic' : 'Unmute mic'}>
              {micOn ? <IconMic /> : <IconMicOff />}
            </button>
            <button className={`ctl ${camOn ? '' : 'is-active'}`} onClick={() => void toggleCam()} aria-label={camOn ? 'Camera off' : 'Camera on'}>
              {camOn ? <IconCam /> : <IconCamOff />}
            </button>
          </div>
        </div>
        <form
          className="card prejoin-form"
          onSubmit={(e) => {
            e.preventDefault();
            join();
          }}
        >
          <p className="lobby-kicker">{initialTier === 'free' ? 'Free room · 720p' : initialTier === 'pass' ? 'Date Night Pass · 1080p60' : 'Couples Pro · 1080p60'}</p>
          <h1>Ready for movie night?</h1>
          <label className="field">
            <span>What should your partner see?</span>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={24} placeholder="Your name" autoFocus />
          </label>
          {mediaProblem && <p className="warn small">{mediaProblem}</p>}
          <button className="btn btn-primary btn-lg" type="submit" disabled={phase === 'joining'}>
            {phase === 'joining' ? 'Joining…' : 'Join the room'}
          </button>
          <p className="muted small">Video and sound go directly between the two of you, encrypted end to end by your browsers.</p>
        </form>
      </div>
    );
  }

  // phase === 'in'
  if (!state || !config) return null;
  const stream = state.stream;
  const iAmSharing = stream.mode === 'screen' && stream.by === selfId && !!capture;
  const sessionLeft = state.session.state === 'running' && state.session.endsAt ? state.session.endsAt - serverNow() : null;
  const cooldownLeft = state.session.state === 'cooldown' && state.session.cooldownEndsAt ? state.session.cooldownEndsAt - serverNow() : null;
  void now; // re-render driver for the clocks above
  const showUi = !idle;
  const qualityLabel = stats?.sending ? `${stats.sending.height}p${stats.sending.fps ? stats.sending.fps : ''}` : stats?.rung ?? quality.label;

  return (
    <div className={`room frame-${state.frame} ${showUi ? '' : 'is-idle'}`}>
      <div className="stage">
        {stream.mode === 'none' && (
          <Lobby state={state} partner={partner} config={config} cooldownLeft={cooldownLeft} onShare={() => void startShare()} onUrl={() => setUrlPrompt(true)} onCopyLink={() => void copyLink()} onAction={onLobbyAction} />
        )}
        {stream.mode === 'screen' && stream.by === selfId && capture && (
          <VideoEl stream={capture.stream} muted={!capture.playLocally} volume={mixer.stream} fit="contain" className="stage-video" />
        )}
        {stream.mode === 'screen' && stream.by !== selfId &&
          (remote.screen ? (
            <VideoEl stream={remote.screen} volume={mixer.stream} fit="contain" className="stage-video" />
          ) : (
            <div className="stage-wait">
              <div className="spinner" />
              <p>Connecting to {partner?.name ?? 'your partner'}’s screen…</p>
            </div>
          ))}
        {stream.mode === 'url' && (
          <UrlPlayer
            playback={stream.url}
            serverNow={serverNow}
            volume={mixer.stream}
            onControl={(playing, position) => socketRef.current?.emit('url:control', { playing, position })}
            onError={(m) => toast(m, { tone: 'warn', ms: 7000 })}
          />
        )}
      </div>

      <div className="room-frame" aria-hidden />

      {partner && (
        <CamBubble
          id="partner"
          stream={remote.cam}
          name={partner.name}
          camOn={partner.camOn}
          micOn={partner.micOn}
          volume={mixer.voice}
          frame={state.frame}
          defaultRect={{ x: 0.78, y: 0.04, w: 0.19 }}
          status={!partner.connected ? 'reconnecting…' : peerState === 'connecting' || peerState === 'new' ? 'connecting…' : peerState === 'failed' ? 'trouble connecting' : undefined}
        />
      )}
      {!selfHidden && (
        <CamBubble
          id="self"
          stream={selfPreview}
          name="You"
          camOn={camOn}
          micOn={micOn}
          muted
          mirrored
          frame={state.frame}
          defaultRect={{ x: 0.78, y: 0.33, w: 0.13 }}
          action={
            <button className="bubble-btn" onClick={toggleSelf} aria-label="Hide my self-view">
              <IconEyeOff width={16} height={16} /> Hide me
            </button>
          }
        />
      )}
      {selfHidden && (
        <button className={`restore-self hover-ui ${showUi ? 'is-visible' : ''}`} onClick={toggleSelf}>
          Show my camera
        </button>
      )}

      <GiftLayer ref={giftLayer} />

      <div className={`hud hover-ui ${showUi ? 'is-visible' : ''}`}>
        <button className={`hud-chip tier-${state.entitlement.tier}`} onClick={() => state.entitlement.tier !== 'pro' && setUpgrade('quality')}>
          {state.entitlement.tier === 'free' ? 'Free' : state.entitlement.tier === 'pass' ? 'Date Night Pass' : 'Couples Pro'} · {qualityLabel}
        </button>
        {sessionLeft !== null && (
          <button className={`hud-chip ${sessionLeft < 5 * 60_000 ? 'is-warn' : ''}`} onClick={() => setUpgrade('warning')}>
            Free hour · {clockText(sessionLeft)} left
          </button>
        )}
        {state.entitlement.tier === 'pass' && state.entitlement.passExpiresAt && (
          <span className="hud-chip">Pass ends {new Date(state.entitlement.passExpiresAt).toLocaleString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' })}</span>
        )}
        {stats?.sending && stats.sending.limitedBy !== 'none' && <span className="hud-chip is-warn">Adapting to your network</span>}
      </div>

      <Controls
        visible={showUi}
        onHold={setHold}
        streamMode={stream.mode}
        iAmSharing={iAmSharing}
        canShare={canShareScreen}
        onShare={() => void startShare()}
        onSwitchSource={() => void switchSource()}
        onStopStream={() => (iAmSharing ? stopShare() : socketRef.current?.emit('stream:stop'))}
        onPlayUrl={() => setUrlPrompt(true)}
        micOn={micOn}
        camOn={camOn}
        onToggleMic={() => void toggleMic()}
        onToggleCam={() => void toggleCam()}
        selfHidden={selfHidden}
        onToggleSelf={toggleSelf}
        streamVolume={mixer.stream}
        voiceVolume={mixer.voice}
        onMixer={setMixer}
        sparks={state.sparks}
        onGift={sendGift}
        onBuySparks={() => setUpgrade('sparks')}
        fullscreen={fullscreen}
        onFullscreen={toggleFullscreen}
        onCopyLink={() => void copyLink()}
        tier={state.entitlement.tier}
        frame={state.frame}
        onFrame={setFrame}
        onUpgrade={() => setUpgrade(state.entitlement.tier === 'free' ? 'manual' : 'frames')}
        onManageBilling={state.entitlement.tier === 'pro' && manageToken ? () => void manageBilling() : null}
        onLeave={leave}
      />

      {urlPrompt && <UrlPrompt onClose={() => setUrlPrompt(false)} onSubmit={playUrl} />}
      {upgrade && (
        <UpgradeSheet roomId={roomId} tier={state.entitlement.tier} reason={upgrade} billingMode={config.billingMode} onClose={() => setUpgrade(null)} onNotice={(t) => toast(t)} />
      )}
      <Toasts toasts={toasts} dismiss={dismiss} />
    </div>
  );
}

function UrlPrompt({ onClose, onSubmit }: { onClose: () => void; onSubmit: (src: string) => void }) {
  const [src, setSrc] = useState('');
  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <form
        className="sheet sheet-small"
        onClick={(e) => e.stopPropagation()}
        onSubmit={(e) => {
          e.preventDefault();
          if (src.trim()) onSubmit(src.trim());
        }}
      >
        <h2>Play a video link together</h2>
        <p className="muted">Paste a direct link to an .mp4, .webm or .m3u8 (HLS) file. Play, pause and seeking stay in sync for both of you.</p>
        <input className="input" value={src} onChange={(e) => setSrc(e.target.value)} placeholder="https://example.com/movie.mp4" autoFocus inputMode="url" />
        <div className="row">
          <button type="button" className="btn btn-ghost" onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary">
            Play for both
          </button>
        </div>
        <p className="muted small">For Netflix, Disney+, YouTube and other apps, use “Share a tab” instead.</p>
      </form>
    </div>
  );
}
