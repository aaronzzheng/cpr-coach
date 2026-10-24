// Dashboard-side session metrics: the session clock, pauses/CCF from any compression source,
// camera-graded compressions, and posture percentages. Posted to the backend after stop,
// which merges them with the watch metrics and computes the score.
import { SESSION, TARGETS } from "../config";
import type { PostureFrame } from "../pose/postureMetrics";

export interface CameraMetrics {
  compressions: number;
  rate_pct: number | null;
  depth_pct: number | null;
  ccf: number | null;
  elapsed_s: number;
  pauses: number;
  longest_pause_s: number;
  avg_rate_cpm: number | null;
  avg_depth_cm: number | null;
  elbow_pct: number | null;
  align_pct: number | null;
  depth_series: [number, number][];
}

function median(xs: number[]): number | null {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

const frac = (xs: boolean[]) => (xs.length ? xs.filter(Boolean).length / xs.length : null);
const round = (x: number, d = 2) => Math.round(x * 10 ** d) / 10 ** d;

export class SessionTracker {
  private clockStart: number | null = null;
  private lastCompression: number | null = null;
  private pauseCount = 0;
  private longestPause = 0;
  private handsOff = 0;

  private rateOk: boolean[] = [];
  private depthOk: boolean[] = [];
  private rates: number[] = [];
  private depths: number[] = [];
  private series: [number, number][] = [];
  private cameraCount = 0;

  private postureTicks = 0;
  private lockedTicks = 0;
  private alignedTicks = 0;

  /** All times are seconds on one monotonic clock; `startedAt` is when "go" was shown. */
  constructor(private readonly startedAt: number) {}

  private settle(now: number): void {
    if (this.clockStart === null && now - this.startedAt >= SESSION.clockGraceS) {
      this.clockStart = this.startedAt + SESSION.clockGraceS;
    }
  }

  /** Any compression, from the watch or the camera. Starts the clock and closes pauses. */
  onCompression(t: number): void {
    if (t < this.startedAt) return; // from before "go"
    if (this.lastCompression !== null && t - this.lastCompression < 0.2) return; // same compression seen twice
    this.settle(t);
    this.clockStart ??= t;
    const gap = t - (this.lastCompression ?? this.clockStart);
    if (gap > TARGETS.pause_threshold_s) {
      this.pauseCount++;
      this.longestPause = Math.max(this.longestPause, gap);
      this.handsOff += gap;
    }
    this.lastCompression = Math.max(t, this.lastCompression ?? t);
  }

  /** A camera-detected compression, graded for the camera-only summary. */
  onCameraCompression(t: number, instRateCpm: number | null, depthCm: number | null): void {
    this.cameraCount++;
    this.onCompression(t);
    if (instRateCpm !== null) {
      this.rates.push(instRateCpm);
      this.rateOk.push(instRateCpm >= TARGETS.rate_min_cpm && instRateCpm <= TARGETS.rate_max_cpm);
    }
    if (depthCm !== null) {
      this.depths.push(depthCm);
      this.depthOk.push(depthCm >= TARGETS.depth_min_cm && depthCm <= TARGETS.depth_max_cm);
      if (this.clockStart !== null) this.series.push([round(t - this.clockStart), round(depthCm)]);
    }
  }

  /** Called every UI tick while running. */
  onPosture(p: PostureFrame | null): void {
    if (!p?.visible) return;
    this.postureTicks++;
    if (p.elbowsLocked) this.lockedTicks++;
    if (p.aligned) this.alignedTicks++;
  }

  elapsed(now: number): number {
    this.settle(now);
    return this.clockStart === null ? 0 : Math.max(0, now - this.clockStart);
  }

  finish(now: number): CameraMetrics {
    const elapsed = this.elapsed(now);
    const enoughPosture = this.postureTicks >= SESSION.minPostureTicks;
    return {
      compressions: this.cameraCount,
      rate_pct: frac(this.rateOk),
      depth_pct: frac(this.depthOk),
      ccf: elapsed > 0 ? Math.max(0, (elapsed - this.handsOff) / elapsed) : null,
      elapsed_s: round(elapsed, 1),
      pauses: this.pauseCount,
      longest_pause_s: round(this.longestPause, 1),
      avg_rate_cpm: median(this.rates),
      avg_depth_cm: median(this.depths),
      elbow_pct: enoughPosture ? this.lockedTicks / this.postureTicks : null,
      align_pct: enoughPosture ? this.alignedTicks / this.postureTicks : null,
      depth_series: this.series,
    };
  }
}
