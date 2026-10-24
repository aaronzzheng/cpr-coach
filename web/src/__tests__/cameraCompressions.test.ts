import { describe, expect, it } from "vitest";
import { CameraCompressionDetector } from "../pose/cameraCompressions";

const FPS = 30;
const H = 720;

/** Gaussian noise via Box-Muller with a seeded LCG so tests are deterministic. */
function rng(seed = 1) {
  let s = seed;
  const u = () => ((s = (s * 1664525 + 1013904223) % 2 ** 32) + 1) / (2 ** 32 + 1);
  return () => Math.sqrt(-2 * Math.log(u())) * Math.cos(2 * Math.PI * u());
}

/** Wrist y (px): moves down by `amp` and back each compression. */
function run(opts: { cpm: number; amp: number; seconds: number; noise?: number; topDrift?: number }) {
  const det = new CameraCompressionDetector();
  const f = opts.cpm / 60;
  const n = rng();
  for (let i = 0; i < opts.seconds * FPS; i++) {
    const t = i / FPS;
    const drift = (opts.topDrift ?? 0) * t;
    const y = 400 + drift + (opts.amp / 2) * (1 - Math.cos(2 * Math.PI * f * t)) + (opts.noise ?? 1) * n();
    det.push(t, y, H);
  }
  return det.state();
}

describe("CameraCompressionDetector", () => {
  it("measures rate, count and amplitude at 110 cpm", () => {
    const s = run({ cpm: 110, amp: 30, seconds: 30 });
    expect(Math.abs(s.rateCpm! - 110)).toBeLessThanOrEqual(3);
    expect(Math.abs(s.count - 55)).toBeLessThanOrEqual(1);
    // EMA smoothing shaves a little amplitude off.
    expect(s.amplitudePx!).toBeGreaterThan(24);
    expect(s.amplitudePx!).toBeLessThan(32);
    expect(s.incompleteRecoil).toBe(false);
  });

  it.each([80, 90, 100, 110, 120, 130, 140])("tracks %i cpm within ±3", (cpm) => {
    const s = run({ cpm, amp: 30, seconds: 20 });
    expect(Math.abs(s.rateCpm! - cpm)).toBeLessThanOrEqual(3);
  });

  it("ignores jitter smaller than the prominence threshold", () => {
    const s = run({ cpm: 110, amp: 4, seconds: 10, noise: 1 });
    expect(s.count).toBeLessThanOrEqual(1);
  });

  it("flags incomplete recoil when the top keeps sinking", () => {
    const s = run({ cpm: 110, amp: 30, seconds: 15, topDrift: 3 });
    expect(s.incompleteRecoil).toBe(true);
  });
});
