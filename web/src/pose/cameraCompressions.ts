// Camera fallback for compressions: finds bottoms/tops in the wrist-y signal with a
// hysteresis (zig-zag) detector, then derives rate, relative depth (px) and a recoil flag.
import { CAMERA_COMPRESSIONS as C } from "../config";

export interface CameraCompression {
  t: number;
  intervalS: number | null;
  instRateCpm: number | null;
  amplitudePx: number | null;
}

export interface CameraCompressionState {
  count: number;
  rateCpm: number | null;
  lastT: number | null;
  /** Median of the last few downstroke amplitudes, in px. */
  amplitudePx: number | null;
  incompleteRecoil: boolean;
}

interface Sample {
  t: number;
  y: number;
}

export function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function percentile(xs: number[], p: number): number {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.max(0, Math.floor(p * (s.length - 1))))];
}

export class CameraCompressionDetector {
  private smoothed: number | null = null;
  /** Image y grows downward, so a compression bottom is a local max of y. */
  private seeking: "bottom" | "top" = "bottom";
  private ext: Sample | null = null;
  private lastBottom: Sample | null = null;
  private lastTop: Sample | null = null;
  private intervals: number[] = [];
  private amplitudes: number[] = [];
  private recent: Sample[] = [];
  private shallowTops = 0;
  private count = 0;

  /** Smoothed wrist-y samples from the last few seconds, for the waveform. */
  trace: Sample[] = [];
  /** Times of recent bottoms, for waveform ticks. */
  ticks: number[] = [];

  /** Feed one wrist-y sample (px). Returns a compression when a bottom is confirmed. */
  push(t: number, yPx: number, frameH: number): CameraCompression | null {
    this.smoothed = this.smoothed === null ? yPx : C.wristEmaAlpha * yPx + (1 - C.wristEmaAlpha) * this.smoothed;
    const s: Sample = { t, y: this.smoothed };

    this.recent.push(s);
    while (this.recent.length && t - this.recent[0].t > C.recoilWindowS) this.recent.shift();
    this.trace.push(s);
    while (this.trace.length && t - this.trace[0].t > C.traceS) this.trace.shift();
    while (this.ticks.length && t - this.ticks[0] > C.traceS) this.ticks.shift();

    const prom = C.prominenceFrac * frameH;
    if (!this.ext) {
      this.ext = s;
      return null;
    }

    if (this.seeking === "bottom") {
      if (s.y >= this.ext.y) this.ext = s;
      else if (this.ext.y - s.y >= prom) {
        const bottom = this.ext;
        this.seeking = "top";
        this.ext = s;
        return this.commitBottom(bottom);
      }
    } else {
      if (s.y <= this.ext.y) this.ext = s;
      else if (s.y - this.ext.y >= prom) {
        this.commitTop(this.ext);
        this.seeking = "bottom";
        this.ext = s;
      }
    }
    return null;
  }

  private commitBottom(b: Sample): CameraCompression | null {
    if (this.lastBottom && b.t - this.lastBottom.t < C.minDistanceS) return null;

    const intervalS = this.lastBottom ? b.t - this.lastBottom.t : null;
    if (intervalS !== null && intervalS <= C.maxIntervalS) {
      this.intervals.push(intervalS);
      if (this.intervals.length > C.rateWindow) this.intervals.shift();
    }
    const amplitudePx =
      this.lastTop && (!this.lastBottom || this.lastTop.t > this.lastBottom.t) ? b.y - this.lastTop.y : null;
    if (amplitudePx !== null) {
      this.amplitudes.push(amplitudePx);
      if (this.amplitudes.length > C.depthWindow) this.amplitudes.shift();
    }

    this.lastBottom = b;
    this.count++;
    this.ticks.push(b.t);
    return {
      t: b.t,
      intervalS,
      instRateCpm: intervalS !== null && intervalS <= C.maxIntervalS ? 60 / intervalS : null,
      amplitudePx,
    };
  }

  private commitTop(top: Sample): void {
    this.lastTop = top;
    if (!this.lastBottom || this.recent.length < 2) return;
    // Highest wrist position recently reached (smallest y) is the "full recoil" reference.
    const ref = percentile(
      this.recent.map((r) => r.y),
      C.recoilTopPercentile,
    );
    const amplitude = this.lastBottom.y - top.y;
    if (amplitude > 0 && top.y - ref > C.recoilDeficitFrac * amplitude) this.shallowTops++;
    else this.shallowTops = 0;
  }

  state(): CameraCompressionState {
    return {
      count: this.count,
      rateCpm: this.intervals.length ? 60 / median(this.intervals) : null,
      lastT: this.lastBottom?.t ?? null,
      amplitudePx: this.amplitudes.length ? median(this.amplitudes) : null,
      incompleteRecoil: this.shallowTops >= C.recoilConsecutive,
    };
  }

  reset(): void {
    Object.assign(this, new CameraCompressionDetector());
  }
}
