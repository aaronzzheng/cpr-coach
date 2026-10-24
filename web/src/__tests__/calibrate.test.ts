import { describe, expect, it } from "vitest";
import { computeCalibration } from "../calibration/calibrate";

describe("computeCalibration", () => {
  it("scales watch depth so the median reads 5 cm", () => {
    const r = computeCalibration([4.0, 4.1, 3.9, 4.0, 4.2, 3.8, 4.0, 4.1, 3.9, 4.0], []);
    expect(r.depthScale).toBeCloseTo(1.25);
    expect(r.depthScaleOk).toBe(true);
    expect(r.watchCheck!.mean).toBeCloseTo(5, 1);
    expect(r.watchCheck!.sd).toBeLessThan(0.2);
    expect(r.cmPerPx).toBeNull();
  });

  it("flags an implausible scale", () => {
    const r = computeCalibration([1, 1, 1], []);
    expect(r.depthScale).toBeCloseTo(5);
    expect(r.depthScaleOk).toBe(false);
  });

  it("derives camera cm per pixel", () => {
    const r = computeCalibration([], [20, 21, 19, 20, 22]);
    expect(r.cmPerPx).toBeCloseTo(0.25);
    expect(r.cameraCheck!.mean).toBeCloseTo(5.1, 1);
    expect(r.depthScale).toBeNull();
    expect(r.depthScaleOk).toBe(false);
  });
});
