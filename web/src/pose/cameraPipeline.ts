// Camera pipeline: webcam → PoseLandmarker per animation frame → posture tracker and camera
// compression detector, plus the skeleton overlay. Exposes a CameraSnapshot for fusion.
import { POSE, TARGETS } from "../config";
import type { CameraSnapshot } from "../fusion/fuse";
import { CameraCompressionDetector } from "./cameraCompressions";
import { createPoseLandmarker, PoseLandmarker } from "./poseLandmarker";
import { PostureTracker, type Landmark, type PostureFrame } from "./postureMetrics";

export type CameraStatus = "off" | "starting" | "on" | "error";

const nowS = () => performance.now() / 1000;

let landmarkerPromise: Promise<PoseLandmarker> | null = null;

export class CameraPipeline {
  status: CameraStatus = "off";
  error: string | null = null;
  poseFps = 0;

  readonly detector = new CameraCompressionDetector();
  private tracker = new PostureTracker();
  private posture: PostureFrame | null = null;
  private stream: MediaStream | null = null;
  private raf = 0;
  private lastVideoTime = -1;
  private frames: number[] = [];

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly canvas: HTMLCanvasElement,
  ) {}

  async start(): Promise<void> {
    if (this.status === "on" || this.status === "starting") return;
    this.status = "starting";
    this.error = null;
    try {
      landmarkerPromise ??= createPoseLandmarker();
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { width: POSE.videoWidth, height: POSE.videoHeight },
        audio: false,
      });
      this.video.srcObject = this.stream;
      await this.video.play();
      const landmarker = await landmarkerPromise;
      this.status = "on";
      this.loop(landmarker);
    } catch (err) {
      this.stop();
      this.status = "error";
      this.error = err instanceof Error ? err.message : String(err);
    }
  }

  stop(): void {
    cancelAnimationFrame(this.raf);
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.video.srcObject = null;
    this.posture = null;
    this.status = "off";
    this.canvas.getContext("2d")?.clearRect(0, 0, this.canvas.width, this.canvas.height);
  }

  resetSession(): void {
    this.detector.reset();
  }

  snapshot(): CameraSnapshot {
    const c = this.detector.state();
    return {
      on: this.status === "on",
      lastCompressionAgeS: c.lastT === null ? null : nowS() - c.lastT,
      posture: this.posture,
      compressions: c,
      calibratedCmPerPx: null,
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
      if (this.posture.visible && this.posture.wrist) this.detector.push(t, this.posture.wrist.y, h);

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

    g.lineWidth = 3;
    g.strokeStyle = "rgba(255,255,255,0.35)";
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
    const color = p.elbowsLocked && p.aligned ? "#22c55e" : "#f59e0b";
    g.lineWidth = 10;
    g.lineCap = "round";
    g.strokeStyle = color;
    g.beginPath();
    g.moveTo(p.shoulder.x, p.shoulder.y);
    g.lineTo(p.elbow.x, p.elbow.y);
    g.lineTo(p.wrist.x, p.wrist.y);
    g.stroke();

    // Dashed vertical from the shoulder: the "shoulders over hands" reference line.
    g.setLineDash([12, 10]);
    g.lineWidth = 3;
    g.strokeStyle = p.aligned ? "rgba(34,197,94,0.7)" : "rgba(245,158,11,0.9)";
    g.beginPath();
    g.moveTo(p.shoulder.x, p.shoulder.y);
    g.lineTo(p.shoulder.x, p.wrist.y);
    g.stroke();
    g.setLineDash([]);

    if (p.elbowAngleDeg !== null) {
      const label = `${Math.round(p.elbowAngleDeg)}°`;
      g.font = "bold 40px system-ui, sans-serif";
      g.lineWidth = 6;
      g.strokeStyle = "rgba(0,0,0,0.7)";
      g.strokeText(label, p.elbow.x + 18, p.elbow.y);
      g.fillStyle = p.elbowAngleDeg >= TARGETS.elbow_locked_min_deg ? "#22c55e" : "#f59e0b";
      g.fillText(label, p.elbow.x + 18, p.elbow.y);
    }
  }
}
