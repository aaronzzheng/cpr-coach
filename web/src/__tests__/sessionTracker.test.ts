import { describe, expect, it } from "vitest";
import { SessionTracker } from "../session/sessionTracker";
import type { PostureFrame } from "../pose/postureMetrics";

const period = 60 / 110;

describe("SessionTracker", () => {
  it("grades camera compressions and computes CCF with one pause", () => {
    const tr = new SessionTracker(0);
    let t = 1;
    let good = 0;
    let bad = 0;
    for (; t < 15; t += period, good++) tr.onCameraCompression(t, 110, 5.5);
    const resume = t + 3;
    let last = t;
    for (t = resume; t < 30; t += period, bad++) {
      tr.onCameraCompression(t, 130, 4.0);
      last = t;
    }
    const m = tr.finish(last);
    expect(m.pauses).toBe(1);
    expect(m.longest_pause_s).toBeCloseTo(3 + period, 1);
    expect(m.ccf!).toBeGreaterThan(0.85);
    expect(m.ccf!).toBeLessThan(0.9);
    // First stretch in range; after the pause, too fast and too shallow.
    expect(m.rate_pct!).toBeCloseTo(good / (good + bad));
    expect(m.depth_pct!).toBeCloseTo(good / (good + bad));
    expect(m.compressions).toBe(good + bad);
    expect(m.depth_series[0][0]).toBeCloseTo(0);
  });

  it("starts the clock after the grace period if nobody compresses", () => {
    const tr = new SessionTracker(0);
    expect(tr.elapsed(4)).toBe(0);
    expect(tr.elapsed(8)).toBeCloseTo(3);
    tr.onCompression(9);
    expect(tr.finish(10).pauses).toBe(1); // 5 → 9 s with no compressions
  });

  it("ignores a compression seen by both the watch and the camera", () => {
    const tr = new SessionTracker(0);
    tr.onCompression(1.0);
    tr.onCompression(1.05);
    tr.onCompression(4.0);
    expect(tr.finish(4).pauses).toBe(1);
  });

  it("reports posture percentages only with enough visible frames", () => {
    const frame = (locked: boolean, aligned: boolean) => ({ visible: true, elbowsLocked: locked, aligned }) as PostureFrame;
    const tr = new SessionTracker(0);
    for (let i = 0; i < 5; i++) tr.onPosture(frame(true, true));
    expect(tr.finish(1).elbow_pct).toBeNull();
    for (let i = 0; i < 15; i++) tr.onPosture(frame(i % 3 !== 0, true));
    const m = tr.finish(2);
    expect(m.elbow_pct!).toBeCloseTo(15 / 20);
    expect(m.align_pct).toBe(1);
  });
});
