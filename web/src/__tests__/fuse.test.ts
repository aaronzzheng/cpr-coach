import { describe, expect, it } from "vitest";
import { fuse, type CameraSnapshot, type WatchSnapshot } from "../fusion/fuse";

const cam = (over: Partial<CameraSnapshot> = {}): CameraSnapshot => ({
  on: true,
  lastCompressionAgeS: 0.3,
  posture: null,
  compressions: { count: 5, rateCpm: 104, lastT: 1, amplitudePx: 20, incompleteRecoil: false },
  calibratedCmPerPx: 0.25,
  ...over,
});

const watch: WatchSnapshot = {
  rateCpm: 112,
  depthCm: 5.4,
  lastCompressionAgeS: 0.5,
  count: 40,
  hrBpm: 100,
  swapRecommended: false,
  fatigueScore: 0.1,
};

describe("fuse", () => {
  it("uses the camera when there is no watch", () => {
    const l = fuse(null, cam());
    expect(l.rate).toEqual({ cpm: 104, source: "camera" });
    expect(l.depth.cm).toBeCloseTo(5);
    expect(l.depth.estimate).toBe(true);
  });

  it("prefers a fresh watch", () => {
    const l = fuse(watch, cam());
    expect(l.rate.source).toBe("watch");
    expect(l.depth).toMatchObject({ cm: 5.4, estimate: false, source: "watch" });
    expect(l.compressionCount).toBe(40);
  });

  it("falls back to the camera when the watch goes stale", () => {
    const l = fuse({ ...watch, lastCompressionAgeS: 5 }, cam());
    expect(l.rate.source).toBe("camera");
  });

  it("shows nothing when the camera is off and there is no watch", () => {
    const l = fuse(null, cam({ on: false }));
    expect(l.rate.cpm).toBeNull();
    expect(l.posture.available).toBe(false);
  });
});
