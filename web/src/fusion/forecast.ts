// Fatigue forecast: predicts when the rescuer's depth will fall below the target, from the trend
// of recent per-compression watch depths, so the coach can call a swap before quality drops
// rather than after. A least-squares line over the last minute; it only warns when the downward
// slope is statistically clear and the forecast has held for a few seconds. Mirrors the phone's
// SwapForecaster (apple/Sources/iOS/Coach/CoachLogic.swift).
import { FORECAST } from "../config";

export class SwapForecaster {
  private pts: { t: number; d: number }[] = [];
  private since: number | null = null;

  reset(): void {
    this.pts = [];
    this.since = null;
  }

  push(t: number, depth: number): void {
    this.pts.push({ t, d: depth });
    while (this.pts.length && t - this.pts[0].t > FORECAST.windowS) this.pts.shift();
  }

  /** Seconds until the trend crosses `limit`, once the forecast has held for `holdS`. */
  update(now: number, limit: number): number | null {
    const s = this.secondsToShallow(now, limit);
    if (s === null) {
      this.since = null;
      return null;
    }
    this.since ??= now;
    return now - this.since >= FORECAST.holdS ? s : null;
  }

  secondsToShallow(now: number, limit: number): number | null {
    const p = this.pts;
    if (p.length < FORECAST.minPoints || p[p.length - 1].t - p[0].t < FORECAST.minSpanS) return null;
    const n = p.length;
    const mt = p.reduce((a, x) => a + x.t, 0) / n;
    const md = p.reduce((a, x) => a + x.d, 0) / n;
    let stt = 0;
    let std = 0;
    for (const x of p) {
      stt += (x.t - mt) ** 2;
      std += (x.t - mt) * (x.d - md);
    }
    if (stt <= 0) return null;
    const slope = std / stt;
    const intercept = md - slope * mt;
    let sse = 0;
    for (const x of p) sse += (x.d - (intercept + slope * x.t)) ** 2;
    const se = Math.sqrt(sse / Math.max(1, n - 2) / stt);
    if (!(slope < 0 && slope < -FORECAST.significance * se)) return null;
    const dNow = intercept + slope * now;
    if (dNow < limit) return null; // already shallow: the depth rule handles it
    const s = (limit - dNow) / slope;
    return s <= FORECAST.horizonS ? s : null;
  }
}
