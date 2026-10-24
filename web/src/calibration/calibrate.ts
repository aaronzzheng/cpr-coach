// Calibration math (PRD §8.6): from compressions pressed to exactly 5 cm, derive the watch
// depth scale and the camera's cm-per-pixel, plus a "± sd" accuracy check for each.
import { CALIBRATION } from "../config";

export interface Check {
  mean: number;
  sd: number;
}

export interface CalibrationResult {
  depthScale: number | null;
  /** False when the scale falls outside the plausible range: "calibration looks off". */
  depthScaleOk: boolean;
  watchCheck: Check | null;
  cmPerPx: number | null;
  cameraCheck: Check | null;
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function check(xs: number[]): Check {
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
  const sd = Math.sqrt(xs.reduce((a, b) => a + (b - mean) ** 2, 0) / Math.max(1, xs.length - 1));
  return { mean, sd };
}

/** `watchRawCm`: watch depths with the scale divided out. `cameraAmpPx`: wrist travel per compression. */
export function computeCalibration(watchRawCm: number[], cameraAmpPx: number[]): CalibrationResult {
  const [lo, hi] = CALIBRATION.depthScaleRange;
  const raw = watchRawCm.filter((d) => d > 0);
  const amps = cameraAmpPx.filter((a) => a > 0);

  const depthScale = raw.length ? CALIBRATION.targetCm / median(raw) : null;
  const cmPerPx = amps.length ? CALIBRATION.targetCm / median(amps) : null;
  return {
    depthScale,
    depthScaleOk: depthScale !== null && depthScale >= lo && depthScale <= hi,
    watchCheck: depthScale !== null ? check(raw.map((d) => d * depthScale)) : null,
    cmPerPx,
    cameraCheck: cmPerPx !== null ? check(amps.map((a) => a * cmPerPx)) : null,
  };
}
