// Camera pipeline: webcam → PoseLandmarker per animation frame → posture tracker and camera
// compression detector, plus the skeleton overlay. Exposes a CameraSnapshot for fusion.
import { POSE } from "../config";
import type { CameraSnapshot } from "../fusion/fuse";
import { CameraCompressionDetector, type CameraCompression } from "./cameraCompressions";
import { createPoseLandmarker, PoseLandmarker } from "./poseLandmarker";
import { PostureTracker, type Landmark, type PostureFrame } from "./postureMetrics";

export type CameraStatus = "off" | "starting" | "on" | "error";

const nowS = () => performance.now() / 1000;

let landmarkerPromise: Promise<PoseLandmarker> | null = null;

export class CameraPipeline {
  status: CameraStatus = "off";
  error: string | null = null;
  poseFps = 0;
  /** From the calibration wizard; null means "estimate from arm length". */
  calibratedCmPerPx: number | null = null;

  readonly detector = new CameraCompressionDetector();
  private tracker = new PostureTracker();
  private posture: PostureFrame | null = null;
  private stream: MediaStream | null = null;
  private raf = 0;
  private lastVideoTime = -1;
  private frames: number[] = [];
  private newCompressions: CameraCompression[] = [];
  private startToken = 0;

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly canvas: HTMLCanvasElement,
  ) {}

  async start(): Promise<void> {
    if (this.status === "on" || this.status === "starting") return;
    // stop() bumps the token, so a start that finishes after being cancelled (e.g. React's
    // dev-mode double mount) cleans up after itself instead of hijacking the shared <video>.
    const token = ++this.startToken;
    this.status = "starting";
    this.error = null;
    try {
      landmarkerPromise ??= createPoseLandmarker();
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: POSE.videoWidth, height: POSE.videoHeight },
        audio: false,
      });
      if (token !== this.startToken) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      this.stream = stream;
      this.video.srcObject = stream;
      await this.video.play();
      const landmarker = await landmarkerPromise;
      if (token !== this.startToken) return;
      this.status = "on";
      this.loop(landmarker);
    } catch (err) {
      if (token !== this.startToken) return;
      this.stop();
      this.status = "error";
      this.error = err instanceof Error ? err.message : String(err);
    }
  }

  stop(): void {
    this.startToken++;
    cancelAnimationFrame(this.raf);
    this.stream?.getTracks().forEach((t) => t.stop());
    // Only detach our own stream; another pipeline may own the <video> by now.
    if (this.stream && this.video.srcObject === this.stream) this.video.srcObject = null;
    this.stream = null;
    this.posture = null;
    this.status = "off";
    this.canvas.getContext("2d")?.clearRect(0, 0, this.canvas.width, this.canvas.height);
  }

  resetSession(): void {
    this.detector.reset();
    this.newCompressions = [];
  }

  /** Camera compressions detected since the last call. */
  drainCompressions(): CameraCompression[] {
    const out = this.newCompressions;
    this.newCompressions = [];
    return out;
  }

  snapshot(): CameraSnapshot {
    const c = this.detector.state();
    return {
      on: this.status === "on",
      lastCompressionAgeS: c.lastT === null ? null : nowS() - c.lastT,
      posture: this.posture,
      compressions: c,
      calibratedCmPerPx: this.calibratedCmPerPx,
    };
  }

  private loop(landmarker: PoseLandmarker): void {
    const step = () => {
      if (this.status !== "on") return;
      this.raf = requestAnimationFrame(step);
      // detectForVideo is synchronous, so a frame is only processed once the previous finished.
      if (this.video.readyState < 2 || this.video.currentTime === this.lastVideoTime) return;
      this.lastVideoTime = this.video.currentTime;

      const tMs = performance.now();
      const result = landmarker.detectForVideo(this.video, tMs);
      const lms = (result.landmarks[0] as Landmark[] | undefined) ?? null;
      const w = this.video.videoWidth;
      const h = this.video.videoHeight;
      const t = tMs / 1000;

      this.posture = this.tracker.update(lms, w, h, t);
      if (this.posture.visible && this.posture.wrist) {
        const c = this.detector.push(t, this.posture.wrist.y, h);
        if (c) this.newCompressions.push(c);
      }

      this.frames.push(t);
      while (this.frames.length && t - this.frames[0] > 1) this.frames.shift();
      this.poseFps = this.frames.length;

      this.draw(lms, w, h);
    };
    step();
  }

  private draw(lms: Landmark[] | null, w: number, h: number): void {
    const cv = this.canvas;
    if (cv.width !== w || cv.height !== h) {
      cv.width = w;
      cv.height = h;
    }
    const g = cv.getContext("2d");
    if (!g) return;
    g.clearRect(0, 0, w, h);
    if (!lms) return;

    // Faint full skeleton for context; the tracked arm is the one mark that carries status.
    g.lineWidth = 2;
    g.lineCap = "round";
    g.strokeStyle = "rgba(245,245,247,0.22)";
    for (const { start, end } of PoseLandmarker.POSE_CONNECTIONS) {
      const a = lms[start];
      const b = lms[end];
      if ((a.visibility ?? 0) < 0.5 || (b.visibility ?? 0) < 0.5) continue;
      g.beginPath();
      g.moveTo(a.x * w, a.y * h);
      g.lineTo(b.x * w, b.y * h);
      g.stroke();
    }

    const p = this.posture;
    if (!p || !p.visible || !p.shoulder || !p.elbow || !p.wrist) return;
    const ok = p.elbowsLocked && p.aligned;
    const tone = ok ? "#30d158" : "#ff9f0a";

    // Shoulders-over-hands reference: a solid hairline straight down from the shoulder.
    g.lineWidth = 2;
    g.strokeStyle = "rgba(245,245,247,0.35)";
    g.beginPath();
    g.moveTo(p.shoulder.x, p.shoulder.y);
    g.lineTo(p.shoulder.x, p.wrist.y);
    g.stroke();

    g.lineWidth = 8;
    g.lineJoin = "round";
    g.strokeStyle = tone;
    g.beginPath();
    g.moveTo(p.shoulder.x, p.shoulder.y);
    g.lineTo(p.elbow.x, p.elbow.y);
    g.lineTo(p.wrist.x, p.wrist.y);
    g.stroke();
    for (const pt of [p.shoulder, p.elbow, p.wrist]) {
      g.beginPath();
      g.arc(pt.x, pt.y, 9, 0, Math.PI * 2);
      g.fillStyle = "#f5f5f7";
      g.fill();
      g.lineWidth = 3;
      g.strokeStyle = "#000";
      g.stroke();
    }

    if (p.elbowAngleDeg !== null) {
      // Label on a dark pill so it reads over any background; the text stays white.
      const label = `${Math.round(p.elbowAngleDeg)}°`;
      g.font = "600 30px -apple-system, BlinkMacSystemFont, system-ui, sans-serif";
      const tw = g.measureText(label).width;
      const x = p.elbow.x + 22;
      const y = p.elbow.y - 22;
      g.fillStyle = "rgba(0,0,0,0.6)";
      g.beginPath();
      g.roundRect(x, y, tw + 24, 44, 12);
      g.fill();
      g.fillStyle = "#f5f5f7";
      g.fillText(label, x + 12, y + 32);
    }
  }
}
