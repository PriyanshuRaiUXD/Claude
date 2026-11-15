import { QUALITY_LADDER, type QualityProfile, type QualityRung } from '../../shared/catalog';
import type { IceServer, MediaMeta, SignalPayload } from '../../shared/types';

export interface RemoteMedia {
  cam: MediaStream | null;
  screen: MediaStream | null;
}

export interface LinkStats {
  /** Rung the outgoing screen stream is capped to right now. */
  rung: string;
  /** Measured outgoing resolution/fps of the screen stream, when sharing. */
  sending?: { height: number; fps: number; kbps: number; limitedBy: string };
  rttMs?: number;
}

interface PeerOptions {
  iceServers: IceServer[];
  /** Exactly one side is polite: it yields when both sides offer at once. */
  polite: boolean;
  send: (payload: SignalPayload) => void;
  camStream: MediaStream;
  profile: QualityProfile;
  onRemote: (media: RemoteMedia) => void;
  onConnection: (state: RTCPeerConnectionState) => void;
  onStats: (stats: LinkStats) => void;
}

/** Webcam bitrate while a screen is being shared: the bubbles are small, the movie is not. */
const CAM_BITRATE_DURING_STREAM = { sd: 450_000, hd: 1_200_000 };

/**
 * One RTCPeerConnection to the partner, using the "perfect negotiation" pattern so either side
 * can add or remove media at any time without glare. Webcam audio/video ride on two fixed
 * transceivers (tracks are swapped with replaceTrack, no renegotiation); a shared screen adds
 * its own video and stereo audio transceivers for as long as it lasts.
 */
export class PeerLink {
  readonly pc: RTCPeerConnection;
  private makingOffer = false;
  private ignoreOffer = false;
  private queue: Promise<void> = Promise.resolve();
  private closed = false;

  private camAudio: RTCRtpTransceiver;
  private camVideo: RTCRtpTransceiver;
  private screenVideo: RTCRtpTransceiver | null = null;
  private screenAudio: RTCRtpTransceiver | null = null;
  /** The stream id the partner knows our screen by. Kept stable across "switch source". */
  private screenMsid: MediaStream | null = null;
  private screenSourceHeight = 1080;

  private remoteStreams = new Map<string, MediaStream>();
  private remoteMeta: MediaMeta = { cam: '', screen: '' };

  private profile: QualityProfile;
  private ladderIndex = 0;
  private badSamples = 0;
  private goodSamples = 0;
  private lastBytes = 0;
  private lastStatsAt = 0;
  private statsTimer: number;
  private disconnectTimer: number | null = null;

  /**
   * Both partners build their connection at the same moment, so both would offer at once. The
   * polite side resolving that glare by rollback can leave it with no ICE candidates (seen in
   * Chrome). So the polite side holds its first offer until it has answered the other's.
   */
  private holdFirstOffer: boolean;
  private pendingOffer = false;
  private holdTimer: number;
  /** Negotiated but not connected for too long → ICE restart (impolite side only). */
  private watchdog: number;
  private stuckSince = 0;
  private iceRestarts = 0;

  constructor(private readonly opts: PeerOptions) {
    this.profile = opts.profile;
    this.ladderIndex = this.ceiling();
    this.pc = new RTCPeerConnection({ iceServers: opts.iceServers as RTCIceServer[], bundlePolicy: 'max-bundle' });

    const cam = opts.camStream;
    this.camAudio = this.pc.addTransceiver(cam.getAudioTracks()[0] ?? 'audio', { direction: 'sendrecv', streams: [cam] });
    this.camVideo = this.pc.addTransceiver(cam.getVideoTracks()[0] ?? 'video', {
      direction: 'sendrecv',
      streams: [cam],
      sendEncodings: [{ maxBitrate: this.profile.camera.maxBitrate, maxFramerate: this.profile.camera.frameRate }],
    });

    this.pc.onnegotiationneeded = () => void this.negotiate();
    this.pc.onicecandidate = ({ candidate }) => {
      if (candidate) this.opts.send({ candidate: candidate.toJSON() });
    };
    this.pc.ontrack = (event) => this.onTrack(event);
    this.pc.onconnectionstatechange = () => this.onConnectionChange();

    this.holdFirstOffer = opts.polite;
    this.holdTimer = window.setTimeout(() => this.releaseFirstOffer(), 2500);
    this.watchdog = window.setInterval(() => this.checkStuck(), 2000);

    this.sendMeta();
    this.statsTimer = window.setInterval(() => void this.sampleStats(), 2000);
  }

  private releaseFirstOffer(): void {
    if (!this.holdFirstOffer) return;
    this.holdFirstOffer = false;
    if (this.pendingOffer) void this.negotiate();
  }

  private checkStuck(): void {
    if (this.closed) return;
    const state = this.pc.connectionState;
    const negotiated = this.pc.signalingState === 'stable' && !!this.pc.remoteDescription;
    if (state === 'connected' || !negotiated) {
      this.stuckSince = 0;
      if (state === 'connected') this.iceRestarts = 0;
      return;
    }
    this.stuckSince ||= performance.now();
    if (!this.opts.polite && performance.now() - this.stuckSince > 8000 && this.iceRestarts < 5) {
      this.iceRestarts++;
      this.stuckSince = 0;
      this.pc.restartIce();
    }
  }

  // ------------------------------------------------------------ negotiation --

  private async negotiate(): Promise<void> {
    if (this.closed) return;
    if (this.holdFirstOffer) {
      this.pendingOffer = true;
      return;
    }
    this.pendingOffer = false;
    try {
      this.makingOffer = true;
      this.sendMeta();
      await this.pc.setLocalDescription();
      if (this.pc.localDescription) this.opts.send({ description: this.pc.localDescription.toJSON() as SignalPayload['description'] });
    } catch (err) {
      console.warn('[peer] negotiation failed', err);
    } finally {
      this.makingOffer = false;
    }
  }

  /** Signals are processed strictly in order. */
  handleSignal(payload: SignalPayload): void {
    this.queue = this.queue.then(() => this.processSignal(payload)).catch((err) => console.warn('[peer] signal error', err));
  }

  private async processSignal({ description, candidate, meta }: SignalPayload): Promise<void> {
    if (this.closed) return;
    if (meta) {
      this.remoteMeta = meta;
      this.emitRemote();
    }
    if (description) {
      const collision = description.type === 'offer' && (this.makingOffer || this.pc.signalingState !== 'stable');
      this.ignoreOffer = !this.opts.polite && collision;
      if (this.ignoreOffer) return;
      await this.pc.setRemoteDescription({ type: description.type, sdp: preferStereo(description.sdp ?? '') });
      if (description.type === 'offer') {
        this.sendMeta();
        await this.pc.setLocalDescription();
        if (this.pc.localDescription) this.opts.send({ description: this.pc.localDescription.toJSON() as SignalPayload['description'] });
        // Answered the first offer: now it is safe to offer our own media.
        if (this.holdFirstOffer) {
          clearTimeout(this.holdTimer);
          this.releaseFirstOffer();
        }
      }
    } else if (candidate) {
      try {
        await this.pc.addIceCandidate(candidate as RTCIceCandidateInit);
      } catch (err) {
        if (!this.ignoreOffer) throw err;
      }
    }
  }

  private sendMeta(): void {
    this.opts.send({ meta: { cam: this.opts.camStream.id, screen: this.screenMsid?.id ?? '' } });
  }

  private onConnectionChange(): void {
    const state = this.pc.connectionState;
    this.opts.onConnection(state);
    if (this.disconnectTimer) {
      clearTimeout(this.disconnectTimer);
      this.disconnectTimer = null;
    }
    if (state === 'failed') this.pc.restartIce();
    // "disconnected" often heals by itself (Wi-Fi roam). If it doesn't within 4s, restart ICE.
    if (state === 'disconnected') this.disconnectTimer = window.setTimeout(() => this.pc.restartIce(), 4000);
  }

  // ----------------------------------------------------------- remote media --

  private onTrack(event: RTCTrackEvent): void {
    const stream = event.streams[0];
    if (!stream) return;
    this.remoteStreams.set(stream.id, stream);
    const update = () => this.emitRemote();
    stream.onremovetrack = update;
    stream.onaddtrack = update;
    event.track.addEventListener('ended', update);
    event.track.addEventListener('unmute', update);
    event.track.addEventListener('mute', update);
    update();
  }

  private emitRemote(): void {
    const live = (s: MediaStream | undefined) => (s && s.getTracks().some((t) => t.readyState === 'live') ? s : null);
    const screen = this.remoteMeta.screen ? live(this.remoteStreams.get(this.remoteMeta.screen)) : null;
    let cam = this.remoteMeta.cam ? live(this.remoteStreams.get(this.remoteMeta.cam)) : null;
    if (!cam) {
      for (const [id, s] of this.remoteStreams) if (id !== this.remoteMeta.screen && live(s)) cam = s;
    }
    this.opts.onRemote({ cam, screen: screen && screen.getVideoTracks().some((t) => t.readyState === 'live') ? screen : null });
  }

  // ------------------------------------------------------------ local media --

  async setCamTracks(audio: MediaStreamTrack | null, video: MediaStreamTrack | null): Promise<void> {
    await Promise.all([this.camAudio.sender.replaceTrack(audio), this.camVideo.sender.replaceTrack(video)]);
  }

  /** Start, switch or stop the shared screen. Switching swaps tracks in place: the partner sees no gap. */
  async setScreen(capture: { video: MediaStreamTrack; audio: MediaStreamTrack | null; stream: MediaStream } | null): Promise<void> {
    if (!capture) {
      for (const tx of [this.screenVideo, this.screenAudio]) {
        try {
          tx?.stop();
        } catch {
          /* already stopped */
        }
      }
      this.screenVideo = this.screenAudio = null;
      this.screenMsid = null;
      this.sendMeta();
      await this.applyCamBitrate();
      return;
    }

    this.screenSourceHeight = capture.video.getSettings().height ?? this.profile.screen.height;
    this.ladderIndex = this.ceiling();
    this.badSamples = this.goodSamples = 0;

    if (this.screenVideo && this.screenMsid) {
      await this.screenVideo.sender.replaceTrack(capture.video);
      if (capture.audio && this.screenAudio) await this.screenAudio.sender.replaceTrack(capture.audio);
      else if (capture.audio) this.screenAudio = this.addScreenAudio(capture.audio, this.screenMsid);
      else if (this.screenAudio) await this.screenAudio.sender.replaceTrack(null);
    } else {
      this.screenMsid = capture.stream;
      this.sendMeta(); // before the offer, so the partner knows which incoming stream is the screen
      const rung = this.rung();
      this.screenVideo = this.pc.addTransceiver(capture.video, {
        direction: 'sendonly',
        streams: [capture.stream],
        sendEncodings: [{ maxBitrate: rung.maxBitrate, maxFramerate: rung.frameRate, priority: 'high', networkPriority: 'high' }],
      });
      if (capture.audio) this.screenAudio = this.addScreenAudio(capture.audio, capture.stream);
    }
    await this.applyScreenRung();
    await this.applyCamBitrate();
  }

  private addScreenAudio(track: MediaStreamTrack, stream: MediaStream): RTCRtpTransceiver {
    return this.pc.addTransceiver(track, {
      direction: 'sendonly',
      streams: [stream],
      sendEncodings: [{ maxBitrate: this.profile.streamAudioBitrate, priority: 'high', networkPriority: 'high' }],
    });
  }

  /** The room's tier changed (upgrade, pass expiry). */
  async setProfile(profile: QualityProfile): Promise<void> {
    this.profile = profile;
    this.ladderIndex = this.ceiling();
    this.badSamples = this.goodSamples = 0;
    await this.applyScreenRung();
    await this.applyCamBitrate();
    if (this.screenAudio) await setEncoding(this.screenAudio.sender, { maxBitrate: profile.streamAudioBitrate });
  }

  // ----------------------------------------------------- adaptive quality --

  private ceiling(): number {
    const allowed = QUALITY_LADDER.findIndex((r) => (this.profile.id === 'hd' ? true : r.minTier === 'sd'));
    return Math.max(0, allowed);
  }

  private rung(): QualityRung {
    return QUALITY_LADDER[this.ladderIndex]!;
  }

  private async applyScreenRung(): Promise<void> {
    if (!this.screenVideo) return;
    const rung = this.rung();
    const scale = Math.max(1, this.screenSourceHeight / rung.height);
    await setEncoding(this.screenVideo.sender, { maxBitrate: rung.maxBitrate, maxFramerate: rung.frameRate, scaleResolutionDownBy: scale });
  }

  private async applyCamBitrate(): Promise<void> {
    const sharing = !!this.screenVideo;
    const maxBitrate = sharing ? Math.min(this.profile.camera.maxBitrate, CAM_BITRATE_DURING_STREAM[this.profile.id]) : this.profile.camera.maxBitrate;
    await setEncoding(this.camVideo.sender, { maxBitrate, maxFramerate: this.profile.camera.frameRate });
  }

  /**
   * Every 2s: if the outgoing screen is bandwidth/CPU-limited or losing packets, step down one
   * rung; after ~20s of headroom, step back up. The call never drops — only the ceiling moves.
   */
  private async sampleStats(): Promise<void> {
    if (this.closed || this.pc.connectionState !== 'connected') return;
    let rttMs: number | undefined;
    let available: number | undefined;
    try {
      const report = await this.pc.getStats();
      report.forEach((s) => {
        if (s.type === 'candidate-pair' && (s as RTCIceCandidatePairStats).nominated && s.state === 'succeeded') {
          const pair = s as RTCIceCandidatePairStats;
          if (pair.currentRoundTripTime !== undefined) rttMs = Math.round(pair.currentRoundTripTime * 1000);
          available = pair.availableOutgoingBitrate;
        }
      });
      if (!this.screenVideo) {
        this.opts.onStats({ rung: this.rung().label, rttMs });
        return;
      }
      const senderReport = await this.screenVideo.sender.getStats();
      let out: (RTCOutboundRtpStreamStats & { qualityLimitationReason?: string }) | undefined;
      let loss = 0;
      senderReport.forEach((s) => {
        if (s.type === 'outbound-rtp') out = s as typeof out;
        if (s.type === 'remote-inbound-rtp') loss = (s as { fractionLost?: number }).fractionLost ?? 0;
      });
      if (!out) return;

      const now = performance.now();
      const bytes = out.bytesSent ?? 0;
      const kbps = this.lastStatsAt ? Math.round(((bytes - this.lastBytes) * 8) / (now - this.lastStatsAt)) : 0;
      this.lastBytes = bytes;
      this.lastStatsAt = now;

      const rung = this.rung();
      const reason = out.qualityLimitationReason ?? 'none';
      const starved = available !== undefined && available < rung.maxBitrate * 0.5;
      const limited = reason === 'bandwidth' || reason === 'cpu' || loss > 0.05 || starved;
      const roomy = !limited && (available === undefined || available > rung.maxBitrate * 1.5);

      if (limited) {
        this.goodSamples = 0;
        if (++this.badSamples >= 2 && this.ladderIndex < QUALITY_LADDER.length - 1) {
          this.ladderIndex++;
          this.badSamples = 0;
          await this.applyScreenRung();
        }
      } else {
        this.badSamples = 0;
        if (roomy && ++this.goodSamples >= 10 && this.ladderIndex > this.ceiling()) {
          this.ladderIndex--;
          this.goodSamples = 0;
          await this.applyScreenRung();
        }
      }

      this.opts.onStats({
        rung: this.rung().label,
        rttMs,
        sending: { height: out.frameHeight ?? 0, fps: Math.round(out.framesPerSecond ?? 0), kbps, limitedBy: reason },
      });
    } catch {
      /* stats are best-effort */
    }
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    clearInterval(this.statsTimer);
    clearInterval(this.watchdog);
    clearTimeout(this.holdTimer);
    if (this.disconnectTimer) clearTimeout(this.disconnectTimer);
    this.pc.onnegotiationneeded = this.pc.onicecandidate = this.pc.ontrack = this.pc.onconnectionstatechange = null;
    // Our own tracks belong to the room page, not to the connection: don't stop them here.
    this.pc.close();
    this.remoteStreams.clear();
  }
}

async function setEncoding(sender: RTCRtpSender, patch: Partial<RTCRtpEncodingParameters>): Promise<void> {
  try {
    const params = sender.getParameters();
    if (!params.encodings || params.encodings.length === 0) return; // not negotiated yet; sendEncodings already set
    params.encodings = params.encodings.map((e) => ({ ...e, ...patch }));
    await sender.setParameters(params);
  } catch {
    /* some browsers reject during renegotiation; the next sample retries */
  }
}

/**
 * Ask the far side's Opus encoder for stereo at full bitrate. `stereo=1` in an SDP means "I want
 * to receive stereo", so we add it to every description we receive: then *our* encoder sends
 * stereo to them, and vice versa. Without this, browsers send film soundtracks as mono voice.
 */
export function preferStereo(sdp: string): string {
  const match = sdp.match(/a=rtpmap:(\d+) opus\/48000\/2/i);
  if (!match) return sdp;
  const pt = match[1];
  return sdp.replace(new RegExp(`a=fmtp:${pt} ([^\\r\\n]*)`, 'g'), (line, params: string) => {
    let next = params;
    if (!/stereo=/.test(next)) next += ';stereo=1';
    if (!/sprop-stereo=/.test(next)) next += ';sprop-stereo=1';
    if (!/maxaveragebitrate=/.test(next)) next += ';maxaveragebitrate=510000';
    return line.replace(params, next);
  });
}
