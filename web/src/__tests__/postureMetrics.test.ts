import { describe, expect, it } from "vitest";
import { angleDeg, fromVerticalDeg, PostureTracker, type Landmark } from "../pose/postureMetrics";

/** Build 33 landmarks with the left arm at the given pixel points on a 1000x1000 frame. */
function pose(shoulder: [number, number], elbow: [number, number], wrist: [number, number], vis = 0.9): Landmark[] {
  const lms: Landmark[] = Array.from({ length: 33 }, () => ({ x: 0, y: 0, visibility: 0.1 }));
  lms[11] = { x: shoulder[0] / 1000, y: shoulder[1] / 1000, visibility: vis };
  lms[13] = { x: elbow[0] / 1000, y: elbow[1] / 1000, visibility: vis };
  lms[15] = { x: wrist[0] / 1000, y: wrist[1] / 1000, visibility: vis };
  return lms;
}

describe("geometry", () => {
  it("measures elbow angles", () => {
    expect(angleDeg({ x: 0, y: 0 }, { x: 0, y: 1 }, { x: 0, y: 2 })).toBeCloseTo(180);
    expect(angleDeg({ x: 0, y: 0 }, { x: 0, y: 1 }, { x: 1, y: 1 })).toBeCloseTo(90);
  });
  it("measures shoulder-over-hands from vertical", () => {
    expect(fromVerticalDeg({ x: 0, y: 0 }, { x: 0, y: 10 })).toBeCloseTo(0);
    expect(fromVerticalDeg({ x: 0, y: 0 }, { x: 10, y: 10 })).toBeCloseTo(45);
    expect(fromVerticalDeg({ x: 0, y: 0 }, { x: -10, y: 10 })).toBeCloseTo(45);
  });
});

describe("PostureTracker", () => {
  const straight = pose([500, 300], [500, 450], [500, 600]);
  const bent = pose([500, 300], [400, 450], [500, 600]);

  it("reports locked and aligned for a straight vertical arm", () => {
    const f = new PostureTracker().update(straight, 1000, 1000, 0);
    expect(f.visible).toBe(true);
    expect(f.elbowsLocked).toBe(true);
    expect(f.aligned).toBe(true);
    expect(f.armLengthPx).toBeCloseTo(300);
  });

  it("only flags a bent elbow after the hold time, and fills the window", () => {
    const tr = new PostureTracker();
    let f = tr.update(bent, 1000, 1000, 0);
    for (let t = 0; t <= 0.4; t += 1 / 30) f = tr.update(bent, 1000, 1000, t);
    expect(f.elbowsLocked).toBe(false);
    expect(f.elbowViolation).toBe(false);
    for (let t = 0.4; t <= 2.5; t += 1 / 30) f = tr.update(bent, 1000, 1000, t);
    expect(f.elbowViolation).toBe(true);
    expect(f.elbowViolationFrac).toBeGreaterThan(0.6);
  });

  it("treats a low-visibility arm as not visible", () => {
    const f = new PostureTracker().update(pose([500, 300], [500, 450], [500, 600], 0.3), 1000, 1000, 0);
    expect(f.visible).toBe(false);
    expect(f.elbowsLocked).toBeNull();
  });
});
