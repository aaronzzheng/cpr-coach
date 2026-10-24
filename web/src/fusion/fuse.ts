// Fusion: merges watch (from the backend) and camera (computed in-browser) into one LiveState
// that every component and the coach engine read. Watch wins for rate/depth when fresh.
import { COACH, FUSION, POSE } from "../config";
import type { CameraCompressionState } from "../pose/cameraCompressions";
import type { PostureFrame } from "../pose/postureMetrics";

export type Source = "watch" | "camera" | null;

export interface WatchSnapshot {
  rateCpm: number | null;
  depthCm: number | null;
  lastCompressionAgeS: number | null;
  count: number;
  hrBpm: number | null;
  swapRecommended: boolean;
  fatigueScore: number;
}

export interface CameraSnapshot {
  on: boolean;
  /** Seconds since the last camera compression, or null if none yet. */
  lastCompressionAgeS: number | null;
  posture: PostureFrame | null;
  compressions: CameraCompressionState;
  /** From calibration (M4); otherwise estimated from arm length. */
  calibratedCmPerPx: number | null;
}

export interface LiveState {
  rate: { cpm: number | null; source: Source };
  depth: { cm: number | null; estimate: boolean; source: Source; drivesCoach: boolean };
  lastCompressionAgeS: number | null;
  compressionCount: number;
  posture: {
    available: boolean;
    elbowAngleDeg: number | null;
    alignAngleDeg: number | null;
    elbowViolation: boolean;
    alignViolation: boolean;
    incompleteRecoil: boolean | null;
  };
  hrBpm: number | null;
  swapRecommended: boolean;
  /** 0–1, watch only. */
  fatigueScore: number | null;
  /** Forecast seconds until depth drops below target (set by the app from SwapForecaster). */
  swapInS: number | null;
}

export function cameraCmPerPx(cam: CameraSnapshot): number | null {
  if (cam.calibratedCmPerPx !== null) return cam.calibratedCmPerPx;
  const arm = cam.posture?.armLengthPx;
  return arm ? POSE.armLengthCm / arm : null;
}

export function fuse(watch: WatchSnapshot | null, cam: CameraSnapshot): LiveState {
  const watchFresh =
    watch !== null && watch.lastCompressionAgeS !== null && watch.lastCompressionAgeS <= FUSION.watchFreshS;
  const camFresh = cam.on && cam.lastCompressionAgeS !== null && cam.lastCompressionAgeS <= FUSION.staleS;

  let rate: LiveState["rate"] = { cpm: null, source: null };
  let depth: LiveState["depth"] = { cm: null, estimate: false, source: null, drivesCoach: false };

  if (watchFresh) {
    rate = { cpm: watch.rateCpm, source: "watch" };
    if (watch.depthCm !== null) depth = { cm: watch.depthCm, estimate: false, source: "watch", drivesCoach: true };
  } else if (camFresh) {
    rate = { cpm: cam.compressions.rateCpm, source: "camera" };
  }

  if (depth.cm === null && camFresh && cam.compressions.amplitudePx !== null) {
    const k = cameraCmPerPx(cam);
    if (k !== null) {
      depth = {
        cm: cam.compressions.amplitudePx * k,
        estimate: true,
        source: "camera",
        drivesCoach: COACH.useCameraDepth,
      };
    }
  }

  const ages = [watch?.lastCompressionAgeS ?? null, cam.on ? cam.lastCompressionAgeS : null].filter(
    (a): a is number => a !== null,
  );

  const p = cam.on ? cam.posture : null;
  const postureOk = p !== null && p.visible;

  return {
    rate,
    depth,
    lastCompressionAgeS: ages.length ? Math.min(...ages) : null,
    compressionCount: watchFresh ? watch.count : cam.compressions.count,
    posture: {
      available: postureOk,
      elbowAngleDeg: postureOk ? p.elbowAngleDeg : null,
      alignAngleDeg: postureOk ? p.alignAngleDeg : null,
      elbowViolation: postureOk && p.elbowViolationFrac >= POSE.postureWindowFrac,
      alignViolation: postureOk && p.alignViolationFrac >= POSE.postureWindowFrac,
      incompleteRecoil: camFresh ? cam.compressions.incompleteRecoil : null,
    },
    hrBpm: watch?.hrBpm ?? null,
    swapRecommended: watch?.swapRecommended ?? false,
    fatigueScore: watch?.fatigueScore ?? null,
    swapInS: null,
  };
}
